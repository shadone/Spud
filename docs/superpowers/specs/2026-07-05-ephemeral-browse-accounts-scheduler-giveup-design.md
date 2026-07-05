# Ephemeral browse accounts + persisted scheduler give-up — design

- **Date:** 2026-07-05
- **Status:** approved design — pending implementation plan
- **Area:** SpudDataKit (accounts, scheduler, AppDatabase), Spud (browse navigation)
- **Related:** [diagnostics-logging.md](../../features/diagnostics-logging.md), `SchedulerService`, `AccountImporter`

## Problem

The diagnostics Event Log shows a recurring `site.fetchFailed` error (HTTP 403) for
`aussie.zone` — an instance the user has no account on. Investigation found:

1. **Browsing a remote instance silently creates a durable, first-class account.**
   Tapping a remote community/post/person routes through
   `AppCoordinator` → `AccountService.accountKeychainId(forInstance:)` →
   `AppDatabase.bestAccountKeychainId(forInstance:)` → `ensureInstanceAndSite`, which
   creates an `InstanceRecord`, an empty `SiteRecord` (`name IS NULL`), and a
   **signed-out `AccountRecord`**. That browse account is schema-identical to the user's
   real bootstrap/default reading account (both `isSignedOutAccountType = 1`,
   `isServiceAccount = 0`); the only discriminator today is `isDefault`.

2. **The scheduler then polls that account's site info forever.** Every 5 minutes,
   `SchedulerService.tick()` runs two site-info sweeps:
   - `signedOutAccountsAwaitingSiteInfo` — signed-out accounts whose `site.name IS NULL`
     (this is where the `aussie.zone` browse account lands).
   - `ownerlessSitesAwaitingInfo` — `site` rows with `name IS NULL` and **no account**
     (federation-harvested sites, or what is left behind if a browse account is deleted).
   A permanent 403 means `site.name` is never populated, so the site never leaves the
   sweep — it is retried indefinitely.

3. **Back-off is in-memory only and never gives up.** `SchedulerBackoff` (a dict on the
   service) stretches the retry interval to a 2-hour cap but (a) resets on every app
   relaunch — `aussie.zone` is retried within ~10 s of each launch — and (b) has no
   permanent "stop" rule, so a WAF-blocked instance is polled forever.

Ephemeral in-memory browse scopes (never persisting the account) were rejected as
infeasible: `AccountScope` / `LemmyService` resolve the account from the DB on every
access and `fatalError` if the row is missing, so it would require rewriting every browse
consumer.

## Goals

- Stop the recurring scheduler polling of instances the user only *browsed*, including
  the user's existing `aussie.zone` account (fix applies retroactively on upgrade).
- Keep browsing remote instances working exactly as today (still backed by a persisted
  signed-out account), but distinguish **internally-created ephemeral** accounts from
  **user-created** ones by explicit provenance.
- Give a still-wanted instance's site info one best-effort fetch on demand, so browse
  screens can still show instance name/icon when reachable.
- Make the scheduler permanently stop fetching *any* instance's site info after repeated
  permanent (4xx) failures, with state that survives relaunch — covering user-created
  signed-out accounts and the ownerless-sites list too.

## Non-goals / out of scope

- **No garbage collection / deletion of accounts** (user chose "flagged-but-kept"). No
  site-row cleanup, no risk of deleting accumulated local history or a federated
  community's instance row.
- **No change to the signed-in daily-refresh path.** A signed-in account's `getSite`
  failure can be an auth (401/expired-token) concern; that is a separate, auth-sensitive
  story left as future work. The give-up here applies to the two *site-info* sweeps
  (signed-out-awaiting and ownerless).
- **No ephemeral in-memory scopes** (infeasible, see above).
- **No promotion mechanic.** An ephemeral account stays ephemeral for its lifetime;
  signing in on that instance creates a separate, non-ephemeral signed-in account (the
  natural "promotion").

## Design

### 1. Data model — migration `v29_ephemeralAccountAndSiteGiveUp`

Add the next `DatabaseMigrator` registration in `AppDatabase+Migrations.swift`.

**`account` table:**
- `isEphemeral` — `BOOLEAN NOT NULL DEFAULT 0`. Provenance flag: `true` only for accounts
  auto-created solely to browse a remote instance.

**`site` table (persisted give-up state):**
- `siteInfoConsecutivePermanentFailures` — `INTEGER NOT NULL DEFAULT 0`. Count of
  consecutive *permanent* (4xx) site-info fetch failures; drives abandonment.
- `siteInfoNextAttemptAt` — `DOUBLE` nullable (Unix seconds). Persisted back-off deadline;
  a site is not swept before this instant.

**Backfill (in the same migration):** mark existing browse accounts ephemeral so the fix
applies to current data (including the user's `aussie.zone` account):

```sql
UPDATE account
SET isEphemeral = 1
WHERE isSignedOutAccountType = 1
  AND isDefault = 0
  AND isServiceAccount = 0
```

Rationale: the only way to obtain a non-default, non-service, signed-out account today is
`bestAccountKeychainId`'s auto-create (the bootstrap/default account is `isDefault = 1`).
The worst case of a misclassification (a deliberately-added signed-out instance) is
benign: it merely moves from timer-swept to on-demand-fetched.

Update the `AccountRecord` struct (`Records/Account.swift`) and `SiteRecord` struct to
carry the new columns.

### 2. Browse-account behavior (the targeted fix)

- **Tag on create.** In `AppDatabase.bestAccountKeychainId(forInstance:)`
  (`Importers/AccountImporter.swift`), the auto-created signed-out `AccountRecord` is
  inserted with `isEphemeral = true`. The reuse branches (existing default / existing
  signed-out account for that site) are unchanged — an existing user-created account is
  never re-flagged. All other creation paths (bootstrap/default, "browse as guest",
  sign-in) insert `isEphemeral = false`.
- **Exclude ephemeral from the signed-out sweep.** `signedOutAccountsAwaitingSiteInfo`
  (`SchedulerQueries.swift`) gains `AND account.isEphemeral = 0`.
- **On-demand fetch.** A new best-effort entry point (e.g.
  `AccountService.refreshSiteInfoOnDemandIfNeeded(forAccountKeychainId:)`) is invoked when
  navigating to a browse target. It fires exactly one `getSite` (fire-and-forget, **no
  retry, no recurrence**) *only when* the account's `site.name IS NULL` — so it stops
  firing once site info lands, and for a perpetually-blocked instance it fires at most
  once per user-initiated open. Trigger site: `AppCoordinator.open(_:in:)` / `.navigate`
  community/post/person cases, right after `accountKeychainId(forInstance:)` resolves. An
  on-demand *failure* does **not** touch give-up state (best-effort, user-initiated).

### 3. Persisted give-up (both site-info sweeps)

Replace the in-memory `SchedulerBackoff` role for the two site-info sweeps with the
persisted per-`site` state above. (`SchedulerBackoff.backoffDelay(failureCount:)` — base
5 min, ×2 each failure, 2-hour cap — is reused to compute `siteInfoNextAttemptAt`.)

- **Selection gating (both sweeps).** A site is eligible only when
  `siteInfoConsecutivePermanentFailures < N` **and**
  (`siteInfoNextAttemptAt IS NULL OR siteInfoNextAttemptAt <= now`). Bake both into the
  `signedOutAccountsAwaitingSiteInfo` and `ownerlessSitesAwaitingInfo` queries.
- **Recording a timer-sweep result** (in `SchedulerService`, per site):
  - **Success** → reset: `siteInfoConsecutivePermanentFailures = 0`,
    `siteInfoNextAttemptAt = NULL`. (Site importer already sets `name` on success; do the
    reset in that same success path so *any* successful `getSite` — timer or on-demand —
    un-abandons the site.)
  - **Permanent failure** (4xx, classified via the existing `OutboxFailureClass`) →
    increment `siteInfoConsecutivePermanentFailures`; set
    `siteInfoNextAttemptAt = now + backoffDelay(failureCount: <permanent count>)`.
  - **Transient failure** (5xx / timeout / offline) → leave the permanent count unchanged;
    set a short `siteInfoNextAttemptAt` (e.g. `now + 5 min`). A flaky instance keeps being
    retried and is never abandoned.
- **Abandonment.** When `siteInfoConsecutivePermanentFailures` reaches **N = 5**, the site
  is no longer selected by either timer sweep (via the gate above) — permanent stop of
  *background* polling.
- **Un-abandon.** "Permanent" is permanent for the background timer only. The on-demand
  fetch (user opening the instance) still runs and, on success, resets the give-up state
  via the shared success path — a WAF that later lifts self-heals the moment the user
  visits. No manual reset, no reinstall.

### 4. Diagnostics

- New durable event **`site.giveUp`** (`.notice`), recorded once when a site crosses the
  abandonment threshold, carrying the instance host and `failureCount` — so About → Logs
  explains *why* an instance stopped being polled ("gave up on aussie.zone after 5
  permanent failures"), not just that it was failing.
- `site.fetchFailed` (existing, `.error`, carries instance host) continues, but is now
  bounded by the give-up rather than recurring forever.

## Behavior scenarios (Given/When/Then)

**Browsing a remote instance no longer causes perpetual polling**
- Given I tap a community hosted on an instance I have no account on
- When the app opens it
- Then a signed-out account is created for that instance, flagged ephemeral, and one
  best-effort site-info fetch is attempted for the header
- And that instance is never added to the recurring 5-minute site-info sweep

**Existing browse accounts are fixed on upgrade**
- Given I already have a browse account (e.g. aussie.zone) from before this change
- When the app launches and runs migration v29
- Then that account is flagged ephemeral and the recurring `site.fetchFailed` noise stops

**A permanently blocked wanted instance is eventually abandoned**
- Given a user-created signed-out account whose instance returns 403 every time
- When the scheduler has recorded N=5 consecutive permanent failures (state persisted
  across relaunches)
- Then the scheduler stops polling that instance's site info and records a `site.giveUp`
  event naming the instance

**A recovered instance self-heals**
- Given an instance the scheduler gave up on
- When I open that instance and the on-demand fetch succeeds
- Then its give-up state is cleared and background refresh resumes

**Transient failures never trigger give-up**
- Given an instance returning intermittent 5xx / timeouts
- When the scheduler retries it
- Then it backs off but is never abandoned (permanent-failure count stays 0)

## Testing plan (Swift Testing, SpudDataKitTests)

- `bestAccountKeychainId` flags an auto-created browse account `isEphemeral = true`; reused
  and bootstrap/default accounts stay `false`.
- `signedOutAccountsAwaitingSiteInfo` excludes ephemeral accounts.
- The migration backfill flips existing non-default, non-service, signed-out accounts to
  ephemeral.
- On-demand refresh fires once when `site.name IS NULL`, and not when it is populated.
- Give-up: N permanent failures abandons the site (excluded from both sweeps); the state
  is read from the DB (survives a simulated relaunch — new service instance, same DB).
- A success resets/un-abandons; a transient failure never increments the permanent count.
- `ownerlessSitesAwaitingInfo` honors the same give-up gate.
- Diagnostics: a `site.giveUp` event is recorded at the threshold (assert via a
  `DiagnosticLogSpy`).

## Docs plan

- `docs/features/` — capability doc for account provenance + scheduler site-info behavior
  (Given/When/Then), covering ephemeral browse accounts, on-demand fetch, and persisted
  give-up. Update the README capability table + "Feature coverage by area" map.
- `docs/features/diagnostics-logging.md` — add the `site.giveUp` event and note the bound
  on `site.fetchFailed`.
- Reconcile the adjacent `background-unread-refresh.md` note about scheduler back-off.

## Files touched (anticipated)

- `SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift` — `v29` + backfill.
- `SpudDataKit/Services/AppDatabase/Records/Account.swift` — `isEphemeral`.
- `SpudDataKit/Services/AppDatabase/Records/SiteRecord.swift` — give-up columns.
- `SpudDataKit/Services/AppDatabase/Importers/AccountImporter.swift` — tag on create;
  site-success reset in the site importer.
- `SpudDataKit/Services/AppDatabase/SchedulerQueries.swift` — ephemeral exclusion + give-up
  gate on both sweeps.
- `SpudDataKit/Services/Scheduler/SchedulerService.swift` — record persisted results;
  emit `site.giveUp`.
- `SpudDataKit/Services/Scheduler/SchedulerBackoff.swift` — reuse the delay math against
  persisted state (the in-memory map for the two site-info sweeps is retired).
- `SpudDataKit/Services/Account/AccountService.swift` — `refreshSiteInfoOnDemandIfNeeded`.
- `Spud/App/AppCoordinator.swift` — invoke on-demand refresh on browse navigation.
- Diagnostics category `.site` already exists; add the `site.giveUp` event string.

## Open questions / risks

- **N = 5** and the transient short-retry interval (5 min) are chosen defaults; easy to
  tune.
- The signed-in daily-refresh path keeps its current in-memory back-off (out of scope) —
  a minor inconsistency, noted for a future unification.
- The migration backfill's heuristic could mis-flag a deliberately-added signed-out
  instance as ephemeral; impact is benign (on-demand instead of timer-swept).
