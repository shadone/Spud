# Scheduler Site-Fetch Back-off — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Spec: `docs/superpowers/specs/2026-06-30-scheduler-403-backoff-design.md`.

**Goal:** Stop the 5-minute `SchedulerService` from re-fetching a failing account's site info every tick (the recurring 403) by adding per-account in-memory exponential back-off, with a reset when connectivity returns.

**Architecture:** A pure, fully-testable `SchedulerBackoff` value type holds per-account `(failureCount, nextAttemptAt)` keyed by `keychainId` and computes the back-off schedule. `SchedulerService` (`@MainActor`) owns one instance, gates both account sweeps through it (skip-if-not-due, record success/failure), takes an injectable clock, and subscribes to the existing `ReachabilityMonitoring` to clear back-off + retry on reconnect. No persistence, no migration, no UI, no log-level change.

**Tech Stack:** Swift 6 (language mode 6.0), SpudDataKit, GRDB, Swift Testing (SpudDataKitTests). No LemmyKit change.

## Global Constraints

- **Swift strict concurrency** `SWIFT_STRICT_CONCURRENCY = complete`; new code is Swift 6.0. `SchedulerBackoff` is a `Sendable` value type; `SchedulerService` is `@MainActor`.
- **No emojis** in code/comments/docs/commits. Conventional commit subjects.
- **Branch:** all work on `feat/scheduler-403-backoff` (worktree `.claude/worktrees/scheduler-403-backoff`, spec committed at `ef4c3643`). Verify `git branch --show-current` before EVERY commit. Stage EXPLICIT paths only — NEVER `git add -A`, NEVER stage `__Snapshots__` paths (cosmetic git-annex `M` markers exist). `git status -uall` to see untracked.
- **In-memory only** — NO GRDB migration, NO new `AccountRecord`/`SiteRecord` columns. Back-off state resets on cold launch (intended).
- **Keep unchanged:** the existing `alertService.handle(error, for: .fetchSiteInfo)` call and the `site.fetchFailed` diagnostic event + its level (the observability work wants the failing instance visible). Back-off reduces FREQUENCY only.
- **No classifier:** do NOT add an `OutboxFailureClass` dependency — one uniform consecutive-failure curve covers transient + persistent.
- **After adding files,** run `make -C <worktree> project` before building.
- **SwiftFormat** touched files before the final verify of each task.
- Reuse the outbox's proven reachability-subscription pattern (`OutboxService.start()` consuming `reachability.statusStream`); GRDB/async conventions: `.async(onQueue: .global(qos: .userInitiated))` where applicable.

## File Structure

**New — SpudDataKit:**
- `Services/Scheduler/SchedulerBackoff.swift` — the pure back-off value type (state + schedule + decisions). One responsibility, fully unit-testable, no DB/service deps.

**Modified — SpudDataKit:**
- `Services/Scheduler/SchedulerService.swift` — own a `SchedulerBackoff`; injectable `now`; injected `reachabilityMonitor`; gate both account sweeps; reachability reset.
- `Services/Scheduler/SchedulerServiceType.swift` if the init is part of a protocol (check — update only if the initializer signature is declared there).

**Modified — Spud (app):**
- `App/DependencyContainer.swift` — pass `reachabilityMonitor` into the `SchedulerService` initializer (it already owns `reachabilityMonitor`).

**New — SpudDataKitTests:**
- `SchedulerBackoffTests.swift` — pure unit tests (Task 1).
- `SchedulerServiceBackoffTests.swift` — integration tests (Task 2), if the tick is drivable with a fake fetch; otherwise fold the reachability-reset assertion here against the public surface.

---

## Task 1: `SchedulerBackoff` pure value type

**Files:**
- Create: `SpudDataKit/Services/Scheduler/SchedulerBackoff.swift`
- Test: `SpudDataKitTests/SchedulerBackoffTests.swift`

**Interfaces — Produces:**
```swift
/// Per-account exponential back-off for scheduler site-info fetches (in-memory).
/// Pure value type: all time comes in as a `now` parameter so it is fully testable.
struct SchedulerBackoff: Sendable {
    private struct Entry { var failureCount: Int; var nextAttemptAt: Date }
    private var entries: [String: Entry] = [:]

    /// Back-off schedule in scheduler-time: ~5 min, doubling, capped at ~2 h.
    /// failureCount 1→5m, 2→10m, 3→20m, 4→40m, 5→80m, 6+→120m (cap).
    static func backoffDelay(failureCount: Int) -> TimeInterval {
        let base: TimeInterval = 5 * 60
        let cap: TimeInterval = 2 * 60 * 60
        let doublings = max(0, failureCount - 1)
        return min(cap, base * pow(2, Double(doublings)))
    }

    /// True when the account may be attempted now (no entry, or `now` past its window).
    func shouldAttempt(keychainId: String, now: Date) -> Bool {
        guard let entry = entries[keychainId] else { return true }
        return now >= entry.nextAttemptAt
    }

    /// Record a fetch outcome: success clears back-off; failure increments and reschedules.
    mutating func recordResult(keychainId: String, succeeded: Bool, now: Date) {
        if succeeded {
            entries[keychainId] = nil
        } else {
            let count = (entries[keychainId]?.failureCount ?? 0) + 1
            entries[keychainId] = Entry(
                failureCount: count,
                nextAttemptAt: now.addingTimeInterval(Self.backoffDelay(failureCount: count))
            )
        }
    }

    /// Clear all back-off (used on reconnect).
    mutating func reset() { entries.removeAll() }
}
```

- [ ] **Step 1: Write the failing test** — `SchedulerBackoffTests` (Swift Testing, `import Foundation`):
```swift
@Test func backoffDelay_schedule() {
    #expect(SchedulerBackoff.backoffDelay(failureCount: 1) == 5 * 60)
    #expect(SchedulerBackoff.backoffDelay(failureCount: 2) == 10 * 60)
    #expect(SchedulerBackoff.backoffDelay(failureCount: 4) == 40 * 60)
    #expect(SchedulerBackoff.backoffDelay(failureCount: 6) == 2 * 60 * 60) // capped
    #expect(SchedulerBackoff.backoffDelay(failureCount: 20) == 2 * 60 * 60) // stays capped
}

@Test func shouldAttempt_trueWhenNoEntry() {
    let b = SchedulerBackoff()
    #expect(b.shouldAttempt(keychainId: "a", now: Date(timeIntervalSince1970: 0)))
}

@Test func failure_thenSkippedWithinWindow_thenDueAfter() {
    var b = SchedulerBackoff()
    let t0 = Date(timeIntervalSince1970: 1000)
    b.recordResult(keychainId: "a", succeeded: false, now: t0) // count 1 → +5m
    #expect(!b.shouldAttempt(keychainId: "a", now: t0.addingTimeInterval(60)))   // within window
    #expect(b.shouldAttempt(keychainId: "a", now: t0.addingTimeInterval(5 * 60))) // at window
}

@Test func consecutiveFailures_climb() {
    var b = SchedulerBackoff()
    let t = Date(timeIntervalSince1970: 0)
    b.recordResult(keychainId: "a", succeeded: false, now: t) // 1 → +5m
    b.recordResult(keychainId: "a", succeeded: false, now: t) // 2 → +10m
    #expect(!b.shouldAttempt(keychainId: "a", now: t.addingTimeInterval(9 * 60)))
    #expect(b.shouldAttempt(keychainId: "a", now: t.addingTimeInterval(10 * 60)))
}

@Test func success_clearsBackoff() {
    var b = SchedulerBackoff()
    let t = Date(timeIntervalSince1970: 0)
    b.recordResult(keychainId: "a", succeeded: false, now: t)
    b.recordResult(keychainId: "a", succeeded: true, now: t)
    #expect(b.shouldAttempt(keychainId: "a", now: t)) // cleared → due
}

@Test func reset_clearsAll() {
    var b = SchedulerBackoff()
    let t = Date(timeIntervalSince1970: 0)
    b.recordResult(keychainId: "a", succeeded: false, now: t)
    b.reset()
    #expect(b.shouldAttempt(keychainId: "a", now: t))
}
```
- [ ] **Step 2:** `make project`; run `-only-testing:SpudDataKitTests/SchedulerBackoffTests`; verify FAIL (type not found).
- [ ] **Step 3:** Create `SchedulerBackoff.swift` (the struct above, BSD-2-Clause header, `import Foundation`, `///` docs).
- [ ] **Step 4:** Run the test; verify PASS (6/6).
- [ ] **Step 5:** SwiftFormat; commit `feat(scheduler): SchedulerBackoff per-account exponential back-off`.

---

## Task 2: Integrate into `SchedulerService` (both sweeps + clock + reconnect reset)

**Files:**
- Modify: `SpudDataKit/Services/Scheduler/SchedulerService.swift`
- Modify: `Spud/App/DependencyContainer.swift` (pass `reachabilityMonitor`)
- Modify (only if needed): `SpudDataKit/Services/Scheduler/SchedulerServiceType.swift` (if the init is protocol-declared)
- Test: `SpudDataKitTests/SchedulerServiceBackoffTests.swift`

**Interfaces — Consumes:** `SchedulerBackoff` (Task 1), the existing `ReachabilityMonitoring` (from `DependencyContainer.reachabilityMonitor`).

**What to do (read `SchedulerService.swift` + `SchedulerQueries.swift` + `OutboxService.start()` first):**
1. Add stored state: `private var backoff = SchedulerBackoff()`, an injectable `private let now: @Sendable () -> Date` (default `Date.init`), and a `private let reachabilityMonitor: ReachabilityMonitoring` (new init param; default-construct is NOT appropriate — inject it). Update the initializer; pass `reachabilityMonitor` from `DependencyContainer` (it already owns one). If `now` is added with a default it won't disturb existing callers.
2. **Gate both account sweeps.** In each per-account loop that calls `fetchSiteInfo(forAccountKeychainId:)` (the signed-in MyUserInfo sweep and the signed-out site-info sweep), wrap the call:
   - `guard backoff.shouldAttempt(keychainId: keychainId, now: now()) else { continue }` BEFORE the fetch.
   - On the fetch's outcome, `backoff.recordResult(keychainId: keychainId, succeeded: <bool>, now: now())`. The existing `fetchSiteInfo` swallows errors and calls `alertService.handle` — refactor minimally so the loop learns success vs failure (e.g. have `fetchSiteInfo` return `Bool`, or wrap the call in a `do/catch` at the loop and keep `fetchSiteInfo` throwing — pick the smaller diff; the existing `alertService.handle` + `site.fetchFailed` diagnostic must still fire on failure, unchanged). Do this via ONE shared private helper so signed-in and signed-out paths can't drift.
3. **Reconnect reset.** In `startService()`, subscribe to `reachabilityMonitor.statusStream` (mirror `OutboxService.start()`); on a transition TO online, `backoff.reset()` and fire a tick (`timer?.fire()` or call `tick()` directly) so previously-failing accounts retry promptly. Keep the subscription `@MainActor`-safe; store the `Task`/cancellable and cancel on teardown/`stopService` if one exists.
4. Do NOT change the queries, the upsert path, or the failure logging/diagnostic.

- [ ] **Step 1: Write the failing test** — `SchedulerServiceBackoffTests` (Swift Testing). Construct a `SchedulerService` with an in-memory `AppDatabase` seeded with a signed-out account awaiting site info, a fake `LemmyService`/`AccountService` whose `getSiteInfo` always throws, an injected `now` you control, and a fake `ReachabilityMonitoring`. Assert: (a) first `tick()` attempts the fetch (fake records 1 call); (b) an immediate second `tick()` (clock unchanged) does NOT attempt it again (still 1 call — backed off); (c) after advancing `now` past the 5-min window, `tick()` attempts again (2 calls); (d) flipping the fake reachability to online clears back-off so the very next `tick()` (clock unchanged) attempts again. If wiring a full fake fetch into the tick proves too heavy, fall back to asserting the gating via a thin testable seam (expose the per-account attempt decision) AND keep the SchedulerBackoff unit coverage as the primary proof — note the choice in the report.
- [ ] **Step 2:** `make project`; run the new test; verify FAIL.
- [ ] **Step 3:** Implement steps 1–4 above.
- [ ] **Step 4:** Run the new test; verify PASS. Then run the full `-only-testing:SpudDataKitTests` to confirm no regressions (the scheduler init change must not break other callers/tests). Build the app: `cd <worktree> && python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud` → SUCCESS.
- [ ] **Step 5:** SwiftFormat; commit `feat(scheduler): gate site-fetch with back-off + reconnect reset`.

---

## Task 3: Docs

**Files:**
- Modify: the relevant `docs/features/` doc covering background account/site refresh (find it — likely an accounts or a diagnostics/refresh doc) + `docs/features/README.md` if a capability line applies. Reconcile the diagnostics doc's mention of the recurring 403 (it's now backed off, not every-5-min).

- [ ] **Step 1:** Document the back-off behavior (a sentence or two + a Given/When/Then: a failing instance is retried with growing back-off and stops spamming the log; reconnecting retries promptly; the failure is still visible once in About → Logs). Honest `Status:`. No `.swift` links.
- [ ] **Step 2:** Commit `docs: scheduler site-fetch back-off`.

---

## Self-review

- **Spec coverage:** pure back-off type + schedule + decisions (T1); SchedulerService integration gating both sweeps + injected clock + reachability reset + DI wiring (T2); docs (T3). In-memory/no-migration, keep-diagnostic-visible, no-classifier, no-log-level-change all honored.
- **Type consistency:** `SchedulerBackoff` API (`backoffDelay`/`shouldAttempt`/`recordResult`/`reset`), the `now: @Sendable () -> Date` injection, and the `reachabilityMonitor: ReachabilityMonitoring` param are used identically across T1/T2.
- **Risk:** the one shared per-account helper (T2) prevents the two sweeps from drifting; the reachability subscription mirrors the proven outbox pattern.
