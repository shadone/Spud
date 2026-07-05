# Account provenance and site-info refresh

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped — pending release (on `feat/ephemeral-browse-accounts`)
- **Related:** [Instance browsing](instance-browsing.md), [Signed-out browsing](signed-out-browsing.md), [Background unread refresh](background-unread-refresh.md), [Diagnostics logging](diagnostics-logging.md), [docs/superpowers/specs/2026-07-05-ephemeral-browse-accounts-scheduler-giveup-design.md](../superpowers/specs/2026-07-05-ephemeral-browse-accounts-scheduler-giveup-design.md)

## What it does

When you navigate to a community, post, or person hosted on an instance you have no account
on, Spud silently creates a signed-out account for that instance so the app can resolve
its content. Accounts created this way are flagged **ephemeral** — they are excluded from
the recurring 5-minute site-info sweep, so browsing a remote instance no longer causes
indefinite background polling of it. Instead, one best-effort site-info fetch is made on
demand the first time the instance is opened (to populate its display name and icon), and
then the instance is left alone.

For user-created signed-out accounts (and ownerless sites harvested by federation), the
scheduler continues its regular sweep. However, if an instance's site-info fetch fails
permanently (HTTP 4xx) N = 5 consecutive times, the scheduler permanently gives up on
that site. The give-up state survives app relaunches. If the instance later recovers and
a successful fetch lands — either from the scheduler, or from a user opening the instance
— the give-up state is cleared and background refresh resumes automatically.

## Behavior and rules

- **Ephemeral flag set on creation.** Accounts auto-created solely to browse a remote
  instance are inserted with `isEphemeral = true`. Accounts created by signing in, by the
  bootstrap / default reading account, or by "Browse as guest" are not ephemeral.
- **No promotion.** An ephemeral account remains ephemeral for its lifetime. Signing in on
  that instance creates a separate, non-ephemeral signed-in account; the ephemeral row is
  not modified.
- **Excluded from the signed-out sweep.** The scheduler's `signedOutAccountsAwaitingSiteInfo`
  query filters out ephemeral accounts. They never appear in that sweep's polling set.
- **One on-demand fetch when site info is missing.** When navigating to an instance whose
  `site.name IS NULL`, Spud fires one best-effort `getSite` call (fire-and-forget, no retry,
  no back-off, no recurrence). Once `site.name` is populated the on-demand fetch stops
  firing. A failure from the on-demand fetch does not touch give-up state.
- **Existing browse accounts are backfilled on upgrade.** Migration `v29` marks all
  existing non-default, non-service, signed-out accounts as ephemeral, so the fix applies
  retroactively without requiring any user action.
- **Persisted give-up for persistent permanent failures.** After N = 5 consecutive
  permanent (4xx) site-info failures from the scheduler, a site's give-up state is written
  to the database. Both scheduler sweeps (`signedOutAccountsAwaitingSiteInfo` and
  `ownerlessSitesAwaitingInfo`) skip sites in the given-up state. The state survives cold
  relaunches.
- **Transient failures never count toward give-up.** 5xx responses and network timeouts
  do not increment the permanent-failure count. They apply a short back-off (approximately
  5 minutes) but the instance is never abandoned for transient reasons.
- **Persisted exponential back-off.** Each scheduler failure (permanent or transient)
  records a `siteInfoNextAttemptAt` deadline in the database (base 5 min, doubling, ≈2 h
  cap). A cold relaunch no longer resets this state, so a persistently-failing instance is
  not re-probed within seconds of every launch.
- **Give-up is self-healing.** The on-demand fetch (user navigating to the instance) still
  fires regardless of give-up state. A successful `getSite` — from any path — resets the
  permanent-failure count, clears `siteInfoNextAttemptAt`, and allows background refresh to
  resume on the next scheduler tick.
- **Give-up is recorded in About → Logs.** A `site.giveUp` notice event names the instance
  and the failure count, making it easy to see which server the scheduler stopped polling
  and why.
- **No account deletion or garbage collection.** Ephemeral accounts are flagged but kept
  indefinitely. No local history, federated community rows, or accumulated browse data is
  removed.

## Scenarios

### Browsing a remote instance no longer causes perpetual polling

- **Given** I tap a community hosted on an instance I have no account on
- **When** the app opens it
- **Then** a signed-out account is created for that instance, flagged ephemeral, and one
  best-effort site-info fetch is attempted to populate the instance header
- **And** that instance is never added to the recurring 5-minute site-info sweep

### Existing browse accounts are fixed on upgrade

- **Given** I already have a browse account (e.g. `aussie.zone`) from before this change,
  causing recurring `site.fetchFailed` noise in About → Logs
- **When** the app launches and applies migration v29
- **Then** that account is flagged ephemeral and the recurring `site.fetchFailed` log entries stop

### A permanently blocked user-created instance is eventually abandoned

- **Given** I have a user-created signed-out account whose instance returns HTTP 403 on
  every site-info request
- **When** the scheduler has recorded N = 5 consecutive permanent failures, with give-up
  state written to the database and surviving at least one cold relaunch
- **Then** the scheduler stops polling that instance's site info
- **And** a `site.giveUp` notice event is recorded in About → Logs naming the instance and
  the failure count

### A recovered instance self-heals automatically

- **Given** an instance the scheduler gave up on (N = 5 permanent failures)
- **When** I open that instance and the on-demand `getSite` succeeds (e.g. the WAF lifted)
- **Then** its give-up state is cleared and background refresh resumes on the next
  scheduler tick

### Transient failures never trigger give-up

- **Given** an instance whose site-info requests are failing with intermittent 5xx responses
  or network timeouts
- **When** the scheduler retries it
- **Then** the permanent-failure count stays at 0 — the instance is never abandoned
- **And** a short back-off (approximately 5 minutes) is applied before the next retry

### App relaunch no longer resets back-off state

- **Given** a site has already backed off due to repeated failures before the app was
  force-quit
- **When** the app relaunches and the scheduler ticks
- **Then** the persisted `siteInfoNextAttemptAt` deadline is honored — the site is not
  retried within seconds of launch

## Not supported / out of scope

- **No change to the signed-in daily-refresh path.** A signed-in account's `getSite`
  failures are out of scope here (they may indicate expired sessions, which is an
  auth-sensitive concern). The give-up and persisted back-off apply only to the two
  site-info sweeps (signed-out-awaiting and ownerless).
- **No visible UI indicator.** There is no in-app indicator showing that an instance is
  ephemeral or that the scheduler has given up on it. About → Logs is the only diagnostic
  surface.
- **No account deletion or GC.** Ephemeral accounts are flagged, not removed.
- **No promotion mechanic.** Ephemeral accounts are never upgraded in place to non-ephemeral.
  Signing in on the same instance creates a separate signed-in (non-ephemeral) account.
- **Known follow-up.** After a cold relaunch with persisted back-off state, a signed-out or
  ownerless site that was backed off waits out its persisted `siteInfoNextAttemptAt` window
  before being retried — network reconnect no longer triggers an immediate retry for these
  two sweeps (the signed-in daily-refresh path is unaffected and still retries immediately
  on reconnect). This is a minor inconsistency noted for a future unification of the
  in-memory and persisted back-off paths.
