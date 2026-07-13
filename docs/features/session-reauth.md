# Session re-login hint

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped — pending on-device validation (not yet run against a real server)
- **Related:** [Accounts and switching](accounts-and-switching.md), [Login](login.md), [Account provenance and site-info refresh](account-provenance-and-site-refresh.md), [Drafts & Outbox](drafts-and-outbox.md), [docs/superpowers/specs/2026-07-13-session-reauth-hint-design.md](../superpowers/specs/2026-07-13-session-reauth-hint-design.md), [docs/superpowers/plans/2026-07-13-session-reauth-hint.md](../superpowers/plans/2026-07-13-session-reauth-hint.md)

## What it does

When a signed-in account's stored session is rejected by the server as expired or
revoked, Spud detects it, marks the account, and surfaces a quiet "Session
expired" hint in four places, all leading to the same in-place re-login screen —
the instance and username pre-filled, only the password to re-enter. A benign
WAF/CDN block (a bare 403) never triggers the hint, and re-logging in reuses the
existing account rather than creating a duplicate.

## Behavior and rules

- **Detection distinguishes an expired session from a benign block.** A rejected
  authenticated request (invalid/expired login, "not logged in") flags the
  account. A 403 from a WAF or CDN in front of the instance — which looks like a
  permanent failure but has nothing to do with the session — never does.
- **Detected two ways.** Actively, when a signed-in account's periodic background
  site refresh comes back unauthenticated. Immediately, when a vote, save, hide,
  or similar action is rejected for the same reason and rolled back.
- **The flag self-heals.** Any successful authenticated request for the account —
  a background refresh, a vote, a completed re-login — clears the hint
  everywhere it appeared. A transient false positive disappears on its own.
- **Four surfaces, one destination.** The Account tab badge, the Account screen's
  re-login row, the account switcher's per-row affordance, and the blocked-action
  toast all open the same pre-filled re-login screen for the affected account.
- **Re-login is in place.** Submitting the pre-filled screen re-authenticates the
  existing account — same identity, same local data, same position in the
  switcher. It does not create a new account entry.
- **Only real signed-in accounts are ever flagged.** Anonymous (signed-out)
  accounts have no session to expire, so they never show the hint.

## Scenarios

### A session expires while the app is idle

- **Given** a signed-in account whose stored session has been revoked by the
  server
- **When** the app's next background refresh for that account runs
- **Then** the account is marked as needing re-login
- **And** the Account tab shows a "!" badge
- **And** the Account screen shows a prominent "Session expired — Tap to log back
  in" row for that account
- **And**, if more than one account is signed in, the account switcher marks that
  account's row with a "Re-login" affordance

### A blocked action surfaces an immediate toast

- **Given** a signed-in account whose stored session has expired
- **When** I vote, save, or hide something and the action is rejected for that
  reason
- **Then** the action is rolled back
- **And** a "Session expired — Re-login" toast appears
- **When** I tap the toast's Re-login action
- **Then** the re-login screen opens, pre-filled with the account's instance and
  username
- **And**, once I re-enter the password and submit successfully, the hint clears
  from every surface — the tab badge, the Account screen row, and the switcher

### Tapping any hint opens the same pre-filled re-login

- **Given** an account flagged as needing re-login
- **When** I tap the Account screen's re-login row, or the switcher's per-account
  "Re-login" affordance
- **Then** the re-login screen opens for that specific account, instance and
  username pre-filled, password empty
- **And** a successful submit re-authenticates that same account in place — no
  duplicate account is created, and it keeps its place in the switcher

### A WAF/CDN block never shows the hint

- **Given** a signed-in account whose instance sits behind a WAF or CDN that
  returns a bare 403 for unrelated reasons
- **When** a background refresh or an action hits that 403
- **Then** the account is never flagged, and none of the four surfaces show
  anything — the failure is handled the same as before this feature (a rolled
  back action, or a silent refresh retry)

## Not supported / out of scope

- No automatic token refresh — Lemmy has no refresh-token flow, so re-login
  (re-entering the password) is the only recovery path.
- No distinction between *why* the session died (expired vs. revoked vs. the
  instance re-keyed) — every case presents identically as "Session expired."
- No consecutive-failure counter before flagging — a single rejected
  authenticated request is enough, and any single success clears it.
