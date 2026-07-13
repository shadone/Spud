# Session Re-login Hint — Design Spec

**Date:** 2026-07-13
**Status:** Approved (brainstorm) — pending implementation plan

**Goal:** When a signed-in account's stored auth token is genuinely expired/invalid, detect it, mark the account, and surface a quiet "Session expired — Re-login" hint that re-authenticates that account in place — while never prompting for a benign WAF/CDN 403.

---

## 1. Concept

A signed-in account's JWT can silently become invalid (expired, revoked, instance re-keyed). Today the app keeps *showing* the account as signed-in while every authenticated call fails, with no cue to the user. This feature:
1. **Detects** the expired-session condition (distinguishing it from a benign WAF 403).
2. **Marks** the account with a persisted `sessionNeedsReauth` flag.
3. **Surfaces** a non-intrusive hint (ambient badges + an in-the-moment toast when an action is blocked).
4. **Re-authenticates in place** (reuse the account's keychain id — no duplicate account) via the existing login flow, pre-filled with the account's instance + username.

The flag **self-heals**: any successful authenticated result clears it, so a transient false positive disappears on the next refresh.

---

## 2. Detection & classification

### 2.1 The classifier (pure, shared)

A pure function classifies a failure from a `LemmyApiError` (see the enum below) into one of: **authExpired**, or **not** (do not flag). It is the single source of truth used by both trigger points.

`LemmyApiError` cases (`SpudDataKit`-visible via `import LemmyKit`): `.network(Error)`, `.failedToDeserializeResponse`, `.serverError(ErrorResponse)` (`ErrorResponse.error: String`), `.unauthorized(message:)`, `.unknownServerError(httpStatusCode:error:)`, `.unknown(Error)`.

**Classify as `authExpired`:**
- `.unauthorized` (HTTP 401 `incorrect_login`), OR
- `.serverError` whose `error` string is `"not_logged_in"` (HTTP 400 — Lemmy's usual expired-token write response), OR
- `.unknownServerError(httpStatusCode: 401, …)` (v4 `getMyUser` GET /account rejected).

**Classify as NOT auth (never flag):**
- `.unknownServerError(httpStatusCode: 403, …)` — WAF/CDN (this is the whole point: a bare 403 must never trip the flag),
- `.serverError` whose error is `rate_limit*`,
- `.network`, `.unknown`, `.failedToDeserializeResponse`, and any other status/error.

A **fourth** auth signal is NOT an error at all (v3): a signed-in account whose `getSite` refresh **succeeded** but returned **`my_user == nil`**. This is handled at the passive trigger (§2.3), not by the error classifier.

Keep the classifier and its constants (the auth error strings) in ONE small file so the rules are testable and centralized. Do NOT change `OutboxFailureClass` (which correctly treats all these as `.permanent` for rollback purposes) — this classifier is a NEW, narrower "is this specifically an auth-expiry" check layered on top.

### 2.2 Write-side trigger (immediate)

In the outbox's permanent-failure path (`OutboxService`, the `case .permanent` branch that rolls back + emits `OutboxFailure`): run the error through the classifier; if `authExpired`, mark the account (§3) and signal the UI to show the in-the-moment toast (§4). Today `OutboxFailure` carries no error/status — add an `isAuthExpiry: Bool` (or a `reason: .authExpired` case) to `OutboxFailure` so `MainWindow`'s toast handler can branch. The rollback behavior itself is unchanged.

### 2.3 Passive trigger (scheduler `getSite`)

`LemmyService.getSiteInfo()` is the single choke-point (it already fetches site + my-user for a signed-in account). For a **signed-in** account:
- **v4:** the combined fetch throws `.unknownServerError(401)` when `getMyUser` is rejected → classify (authExpired) → mark.
- **v3:** the fetch *succeeds* but `my_user == nil` → mark (the token wasn't accepted). Guard: only treat nil-`my_user` as auth-expiry when the `getSite` **succeeded** (site present) for a **signed-in** account — never on a thrown error (a thrown error goes through the classifier, so a WAF 403 that throws is excluded there).
- **Success with `my_user` present → CLEAR the flag** (self-heal).

`getSiteInfo()` currently returns the `SiteInfo` and the scheduler discards it. It must communicate the auth outcome — either return an auth-outcome alongside, or set the flag internally via the account's `AppDatabase`. Prefer setting the flag through a small `AppDatabase` write so the scheduler/outbox don't each re-implement it; the method that performs the authed fetch owns the set/clear.

### 2.4 Self-healing / clearing

The flag is cleared on ANY successful authenticated result for the account: a `getSite` that returns `my_user`, OR a successful outbox write. This makes a transient false positive (e.g. a one-off partial response) disappear on the next success with no consecutive-count bookkeeping. A successful **re-login** (§3) also clears it explicitly.

---

## 3. Persisted per-account flag + re-login in place

### 3.1 Migration `v37_sessionNeedsReauth`

Add `account.sessionNeedsReauth` (BOOLEAN NOT NULL DEFAULT 0) — the next migration case after `v36_commentChildCount`; never edit an existing migration. Add the field to `AccountRecord` and to `AccountListRow` + its `SELECT` in `AccountListObservations.observeAccountListRows()` so the switcher/Account screen/tab-badge react. Never set it for signed-out / service / ephemeral accounts (only real signed-in accounts).

`AppDatabase` writes: `setAccountSessionNeedsReauth(keychainId:, _ needsReauth: Bool)` (idempotent), used by both triggers to set, and by the success/self-heal + re-login paths to clear.

### 3.2 In-place re-authentication (greenfield — this is the substantive new path)

Today `login(...)` → `storeSignedInCredential` always mints a NEW `keychainId` + inserts a fresh account row (there is no `(siteId, personId)` account uniqueness), so a naive re-login **duplicates** the account. Add:

`AccountService.reauthenticate(keychainId: String, username: String, password: String, totp2faToken: String?) async throws` — performs the same unauthenticated login network call against the account's own instance (resolved from `keychainId`), and on a JWT-bearing success writes the new token to the **existing** keychain id via `writeCredential(_:forKeychainId: keychainId)` (no new row, no new keychain id), refreshes the account's site/my-user, and clears `sessionNeedsReauth`. It must NOT create a duplicate account or change the account's identity/local state. 2FA (`totp2faToken`) and its `totp2faRequired` re-prompt work exactly as `login`'s do.

### 3.3 Pre-fillable, re-auth-mode login UI

`LoginViewController`/`LoginViewModel` are launched from a `SiteListRow` (instance) with `username` defaulting to `""`. Additions:
- an optional `initialUsername` so the username field is pre-filled;
- a "re-auth target" mode: when launched to re-authenticate an existing account (carrying its `keychainId`), a successful submit calls `AccountService.reauthenticate(keychainId:…)` INSTEAD of `login(...)` (which would duplicate). The instance is carried by `SiteListRow.forTypedInstance(account.instance)`; the username comes from the account's stored person name.
- Copy: the screen reads as re-login (e.g. title "Log back in", the instance shown, username pre-filled, password empty). Passwords are never stored, so re-login = "instance + username pre-filled, re-enter password."

A launch helper (app-level) builds this from an account `keychainId`: resolve the account's instance + username, present `LoginViewController` in re-auth mode. All hint tap-targets (§4) call it.

---

## 4. Surfacing

- **Account-tab badge (ambient):** a "!" dot on the Account tab when ANY real account has `sessionNeedsReauth`, reusing the `MainWindow.applyBadge`/tab-`badgeValue` mechanism (same pattern the Inbox unread badge uses). Cleared when no account needs re-auth.
- **Account screen row (ambient):** a prominent top row/section in `AccountView` ("Session expired — Re-login") for the active account when flagged → tap launches re-auth for that account.
- **Account-switcher indicator (ambient, multi-account):** a per-row indicator + "Re-login" affordance in the account-switcher, keyed off the new `AccountListRow` field, so a multi-account user sees WHICH account needs it → tap re-auths that account.
- **In-the-moment toast:** when an action is blocked by an expired session (§2.2), the existing rollback toast becomes "Session expired — tap to re-login" with a tap action into the re-auth flow (NOT a modal; contextual, one per blocked action).

All surfaces route to the same §3.3 re-auth launch helper.

---

## 5. Out of scope (YAGNI)

- Auto-refreshing / silently renewing the token (Lemmy has no refresh-token flow Spud uses; re-login is the mechanism).
- A consecutive-failure counter for detection (the self-heal-on-success makes it unnecessary).
- Distinguishing *why* the session died (expired vs revoked vs re-keyed) — all present as "re-login".
- Changing the outbox rollback behavior or `OutboxFailureClass` permanence rules.
- Any handling of the signed-out/service-account site-info give-up state (separate, already shipped).

---

## 6. Testing

- **Classifier (pure, unit):** each `LemmyApiError` shape → authExpired vs not: `.unauthorized` → yes; `.serverError("not_logged_in")` → yes; `.unknownServerError(401)` → yes; `.unknownServerError(403)` → **no** (WAF); `.serverError("rate_limit")` → no; `.network`/`.unknown` → no.
- **Flag transitions (SpudDataKitTests):** `v37` migration round-trip; `setAccountSessionNeedsReauth` set/clear; only real signed-in accounts flaggable; a successful getSite-with-my_user clears it; `observeAccountListRows` surfaces the flag.
- **Passive trigger:** a signed-in v3 `getSiteInfo` returning `my_user == nil` sets the flag; returning `my_user` clears it; a thrown WAF 403 does NOT set it. (Stub-transport, reusing the `getSite` test harness.)
- **Write-side trigger:** an outbox permanent failure classified as auth sets the flag + marks the `OutboxFailure` as auth-expiry; a 403/other permanent failure does not.
- **`reauthenticate`:** updates the EXISTING keychain id in place (no duplicate account row; same `keychainId`, same person/local state), clears the flag; a wrong password / `totp2faRequired` behaves like `login`.
- **UI/snapshot:** the Account-screen re-login row and the switcher re-login indicator (flagged vs not), recorded on the reference device.

---

## 7. Suggested implementation phasing (for the plan)

Each phase is independently testable:
1. **Data + classifier + flag:** `v37` migration + `AccountRecord`/`AccountListRow` field + `AppDatabase` set/clear writes; the pure auth-expiry classifier + its tests.
2. **Detection wiring:** passive (`getSiteInfo` set/clear) + write-side (outbox classify → flag + `OutboxFailure.isAuthExpiry`).
3. **In-place re-auth:** `AccountService.reauthenticate(...)` (reuse keychain id) + the re-auth-mode / pre-filled `LoginViewController` + the launch helper.
4. **Surfacing:** Account-tab dot + Account-screen row + switcher indicator + the in-the-moment toast; docs.

---

## 8. Docs

New `docs/features/session-reauth.md` (PM-level, Given/When/Then: a session expires → the account is flagged → the hint shows in the Account tab/switcher + a blocked action toasts → tap → re-login pre-filled → flag clears; a WAF 403 never triggers it). Update `docs/features/README.md` capability table + by-area map; reconcile the accounts/login docs.
