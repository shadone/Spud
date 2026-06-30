# Scheduler site-fetch back-off (the recurring 403)

- **Date:** 2026-06-30
- **Status:** design — pending implementation
- **Surfaces:** `iphone`, `ipad` (no visible UI; behavior + logs only)
- **Targets touched:** `SpudDataKit`
- **Replaces/updates docs:** a short note in the relevant `docs/features/` doc (account/site refresh behavior) + reconcile the diagnostics doc's mention of the recurring 403

## Summary

The 5-minute `SchedulerService` refreshes site/account info. When an account's
`getSite` fails (notably a bare CDN/WAF **HTTP 403**, `error: nil`), the fetch
throws before the upsert, so the account stays "awaiting" and is re-attempted on
**every tick, forever, with no back-off** — hammering a failing instance every
5 minutes and filling About → Logs. This adds a per-account exponential back-off
(in-memory) so a persistently-failing account is retried progressively less often
(up to a ~2 h cap) and a transient failure self-heals, with a prompt retry when
network connectivity returns.

## Background — verified current state

- **No back-off / failure state exists anywhere** — no column on `AccountRecord`
  or `SiteRecord`, no in-memory counter in `SchedulerService`. The scheduler is
  `@MainActor` and long-lived, so back-off state can live **in-memory** in the
  service; no GRDB migration needed.
- The tick runs sweeps from `SchedulerQueries.swift`: `signedInAccountsAwaitingMyUserInfo()`
  (`localAccountId IS NULL`), `signedOutAccountsAwaitingSiteInfo()` (`site.name IS NULL`),
  `signedInAccountsStale(updatedBefore:)`, and `ownerlessSitesAwaitingInfo()`.
- On failure, `SchedulerService.fetchSiteInfo(forAccountKeychainId:)` calls
  `alertService.handle(error, for: .fetchSiteInfo)` (log-only) and swallows the
  error; the account row is untouched (`site.name`/`localAccountId` stay NULL,
  `updatedAt` not bumped), so the "awaiting" predicates re-select it next tick.
- The observability feature records a durable `site.fetchFailed` event (category
  `.site`, level `.error`, carries the instance host) on each failure — this is
  intentionally visible in About → Logs and is **kept** (see Non-goals).
- The `DependencyContainer` already owns a `reachabilityMonitor: ReachabilityMonitoring`
  (the outbox subscribes to its status stream); it can be injected into
  `SchedulerService` for the reconnect reset.

## Goals

- A persistently-failing account (e.g. a 403-ing instance) is retried with
  exponential back-off (≈5 min → doubling → ~2 h cap), not every 5 min.
- A transient failure self-heals: the next successful fetch clears the back-off.
- When connectivity returns, back-off is cleared so a previously-failing account
  is retried promptly rather than waiting out its window.
- The About → Logs spam drops to a handful of entries (then rare), purely by
  reducing attempt **frequency** — no log-level change, no hidden failures.

## Non-goals (this iteration)

- **No persisted back-off state / migration.** In-memory only; resets on cold
  launch (a recovered instance retries promptly on the next launch — desirable).
- **No "session needs re-login" UI.** Distinguishing a real 401 from a CDN 403 and
  surfacing a re-login hint is a separate feature (no per-account auth-state UI
  exists today); explicitly deferred.
- **No log-level change.** The durable `site.fetchFailed` event and the OSLog
  error line keep their levels; back-off removes the spam via frequency. (We do
  NOT want to hide which instance is failing — that was the point of the
  observability work.)
- **No error-classifier dependency.** A single consecutive-failure curve handles
  both transient and persistent failures (see Design); `OutboxFailureClass` is not
  needed here.
- **Ownerless-sites sweep** (`ownerlessSitesAwaitingInfo`) is out of scope — low
  volume and has no `keychainId` to key back-off on. (Noted; can be revisited if
  it ever becomes a source of spam.)

## Design

### In-memory per-account back-off in `SchedulerService`

`SchedulerService` (`@MainActor`) gains:

```swift
private struct FetchBackoff {
    var failureCount: Int
    var nextAttemptAt: Date
}
private var fetchBackoff: [String: FetchBackoff] = [:]   // keyed by accountKeychainId
```

A small, testable helper computes the delay (injectable clock for tests):

```swift
/// Exponential back-off in scheduler-time: ~5 min doubling, capped at ~2 h.
/// failureCount 1→5m, 2→10m, 3→20m, 4→40m, 5→80m, 6+→120m.
static func backoffDelay(failureCount: Int) -> TimeInterval {
    let base: TimeInterval = 5 * 60
    let cap: TimeInterval = 2 * 60 * 60
    let doublings = max(0, failureCount - 1)
    return min(cap, base * pow(2, Double(doublings)))
}
```

### Tick integration (both account sweeps)

The per-account fetch in each sweep is gated by the back-off, and updates it:

- **Before attempting** a due account: if `let b = fetchBackoff[keychainId], now() < b.nextAttemptAt` → **skip** this account this tick (it isn't due yet).
- **On `fetchSiteInfo` success:** `fetchBackoff[keychainId] = nil` (reset).
- **On `fetchSiteInfo` failure:** `let count = (fetchBackoff[keychainId]?.failureCount ?? 0) + 1; fetchBackoff[keychainId] = .init(failureCount: count, nextAttemptAt: now() + backoffDelay(failureCount: count))`. (Keep the existing `alertService.handle` + the `site.fetchFailed` diagnostic exactly as-is.)

This wraps the existing per-account call in both `signedIn...` and `signedOut...`
sweeps. Factor a single private helper (e.g. `shouldAttempt(keychainId:)` +
`recordFetchResult(keychainId:succeeded:)`) so both sweeps share one code path
(DRY) and the logic is unit-testable.

### Reconnect reset (reachability)

Inject the existing `reachabilityMonitor: ReachabilityMonitoring` into
`SchedulerService`. In `startService()`, subscribe to its status stream (mirroring
how `OutboxService.start()` consumes `reachability.statusStream`); on a transition
**to online**, clear `fetchBackoff` (`fetchBackoff.removeAll()`) and fire a tick so
previously-failing accounts are retried promptly. Use the same
`.async(onQueue: .global(qos:))`/AsyncStream conventions the codebase uses; keep
the subscription `@MainActor`-safe and cancel it on teardown.

### Clock injection

`now` is an injectable `@Sendable () -> Date` on `SchedulerService` (default
`Date.init`), so tests drive the back-off schedule deterministically without real
time. (Mirrors the `DiagnosticLog` `now` injection pattern.)

## Data flow (persistent 403)

```
tick → account due (site.name NULL) → shouldAttempt? yes (no back-off yet)
     → fetchSiteInfo → 403 → alertService.handle + site.fetchFailed (unchanged)
     → recordFetchResult(failed): count=1, nextAttemptAt = now+5m
tick (+5m) → shouldAttempt? now≈nextAttemptAt → attempt → 403 → count=2, next=+10m
...climbs to the 2h cap; one retry every ~2h instead of every 5m.
network returns → reachability online → fetchBackoff.removeAll() → tick → retry now
getSite succeeds (instance recovered / re-auth) → recordFetchResult(success): entry cleared.
```

## Testing

Unit (`SpudDataKitTests`, Swift Testing; injected clock):
- `backoffDelay(failureCount:)` — schedule (1→5m … 6→cap 2h) and the cap.
- `recordFetchResult` — failure increments count + sets `nextAttemptAt`; success
  clears the entry.
- `shouldAttempt` — true when no entry / `now ≥ nextAttemptAt`; false within the
  window.
- A tick-level test (with a fake site fetch that fails, an injected clock, an
  in-memory `AppDatabase`): a failing account is attempted once, then SKIPPED on
  an immediate next tick (within the window), then attempted again after the clock
  advances past `nextAttemptAt`; a success clears back-off.
- Reconnect: simulate a reachability flip to online (a fake `ReachabilityMonitoring`)
  → `fetchBackoff` is cleared (assert a previously-backed-off account becomes due).

No snapshot/UI tests (no UI change).

## Files (anticipated)

Modified — SpudDataKit:
- `Services/Scheduler/SchedulerService.swift` — back-off state + `backoffDelay` +
  `shouldAttempt`/`recordFetchResult` helpers + tick gating in both sweeps +
  reachability subscription + injected `now`/`reachabilityMonitor`.
- `App/DependencyContainer.swift` (Spud target) — pass `reachabilityMonitor` into
  the `SchedulerService` initializer.
- Possibly `SchedulerServiceType` / the scheduler's protocol if its init signature
  is part of a protocol (check; update if so).

New — SpudDataKitTests:
- `SchedulerBackoffTests.swift` — the unit tests above.

No migration. No new app-target UI.

## Open risks

- **Tick gating must cover both sweeps consistently** — factor one shared helper so
  signed-in and signed-out paths can't drift. The shared helper is the unit-tested
  seam.
- **Reachability subscription lifecycle** — must not leak or double-fire; mirror the
  outbox's proven subscription pattern and cancel on teardown.
- **In-memory reset on launch is intended** — a permanently-down instance will get
  one fresh attempt per cold launch; acceptable (and self-healing if it recovered).
