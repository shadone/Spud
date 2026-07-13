# Session Re-login Hint Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Detect when a signed-in account's stored JWT is genuinely invalid (distinct from a benign WAF/CDN 403), flag the account, surface a quiet "Session expired -- Re-login" hint, and re-authenticate that account in place (reusing its keychain id -- no duplicate account).

**Architecture:** A pure `AuthExpiry` classifier (mirroring the existing `ContentNotFound`) is the single source of truth for "is this specifically an auth-expiry error." Two trigger points feed it: the passive `LemmyService.getSiteInfo()` choke-point (sets/clears a persisted per-account `sessionNeedsReauth` flag on every signed-in site refresh) and the write-side `OutboxService` permanent-failure path (flags + tags the `OutboxFailure`). A new `AccountService.reauthenticate(keychainId:...)` logs in on the account's own instance and writes the new token to the *existing* keychain id. Four ambient/in-the-moment surfaces route to one re-auth launch helper.

**Tech Stack:** Swift 6 (strict concurrency, `@MainActor`), UIKit + SwiftUI, GRDB migrations, Swift Testing, `import LemmyKit`.

## Global Constraints

Copied verbatim from the spec and the project standing rules; every task's requirements include this section.

- **No emojis** in code, comments, docs, or commit messages.
- **Never** paste secrets/JWTs into output or logs. The JWT is written straight to the keychain; never log it.
- **Conventional commit** subjects (`feat:`, `fix:`, `test:`, `docs:`). Small, focused commits.
- **Commit trailers** on every commit:
  ```
  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_011EaJJgwwrWu2oxRdkAZtFY
  ```
- **Stage explicit paths** (never `git add -A`; never `git add` the gitignored `.remember/` or `Spud.xcodeproj`).
- **Swift Testing** for unit tests: `import Testing` (+ `import Foundation` where `Date`/`URL`/`Data` are used), `struct` suites, `@Test func`, `#expect`/`#require`. A suite touching a fixed-path/`.shared` singleton needs `@Suite(.serialized)`; per-test `AppDatabase.inMemory()` is already isolated.
- **Migrations** are append-only. The new one is `v37_sessionNeedsReauth` (latest existing is `v36_commentChildCount`). Never edit an existing migration.
- **Never flag signed-out / service / ephemeral accounts** -- only real signed-in accounts. Every flag write is SQL-guarded with `isServiceAccount = 0 AND isSignedOutAccountType = 0`.
- **A bare 403 must never trip the flag** -- `.unknownServerError(httpStatusCode: 403)` is WAF/CDN, classified NOT auth. This is the whole point of the feature.
- **Native iOS bar:** HIG, SF Symbols, Dynamic Type, light/dark, VoiceOver label+trait on every interactive element, iPhone + iPad both first-class.
- **Docs discipline:** the feature ships `docs/features/session-reauth.md` + the README capability table + the README "Feature coverage by area" map. No `.swift` links in feature docs.
- **Build/test:** `make test-only ONLY=SpudDataKitTests` (or the full `make test`) builds the whole Spud plan -- run it after any change to a VC's `Dependencies` (a missed test double is a LINKER error, not a compile error). Run `mint run swiftformat <changed paths>` BEFORE the final verify, never after. Snapshot refs record on iPhone 17 Pro / iOS 26.3.x via `make snapshot`.
- **Worktree:** all work happens in `/Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/session-reauth` on branch `feat/session-reauth`. Verify `git branch --show-current` is `feat/session-reauth` before each commit.

---

## File Structure

**Task 1 (data + classifier):**
- Create `SpudDataKit/Services/Lemmy/AuthExpiry.swift` -- the pure classifier (mirrors `ContentNotFound.swift`).
- Modify `SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift` -- append `v37_sessionNeedsReauth`.
- Modify `SpudDataKit/Services/AppDatabase/Records/Account.swift` -- add `sessionNeedsReauth` field.
- Create `SpudDataKit/Services/AppDatabase/AccountReauthWrites.swift` -- the `setAccountSessionNeedsReauth` writes + `accountAnyNeedsReauthSync`/`observeAnyAccountNeedsReauth` reads + `accountPersonNameSync`.
- Modify `SpudDataKit/Services/AppDatabase/AccountListObservations.swift` -- add the flag to `AccountListRow` + its SELECT.
- Tests: `SpudDataKitTests/AuthExpiryTests.swift`, `SpudDataKitTests/SessionReauthFlagTests.swift`.

**Task 2 (detection wiring):**
- Modify `SpudDataKit/Services/Lemmy/LemmyService.swift` (`getSiteInfo()`, ~1247-1313) -- passive set/clear.
- Modify `SpudDataKit/Services/Outbox/OutboxService.swift` (`OutboxFailure` struct ~18-23; `.permanent` path ~228-281) -- classify + flag + `OutboxFailure.isAuthExpiry`.
- Tests: extend `SessionReauthFlagTests.swift` (passive + write-side).

**Task 3 (in-place re-auth):**
- Modify `SpudDataKit/Services/Account/AccountService.swift` -- `reauthenticate(...)` + `username(forAccountKeychainId:)` + protocol additions.
- Modify `Spud/Scenes/Account/Login/LoginViewModel.swift` -- `initialUsername` + `reauthTarget`.
- Modify `Spud/Scenes/Account/Login/LoginViewController.swift` -- forward the two params + pre-fill + re-login title.
- Create `Spud/Scenes/Account/AccountReauthLauncher.swift` -- the launch helper.
- Tests: `SpudDataKitTests/AccountReauthenticateTests.swift`.

**Task 4 (surfacing + docs):**
- Modify `Spud/Scenes/MainWindow/MainWindow.swift` -- tab dot + auth-expiry toast branch.
- Modify `Spud/Scenes/Account/AccountViewModel.swift` + `AccountView.swift` + `AccountViewController.swift` -- Account-screen re-login row.
- Modify `Spud/Scenes/Account/AccountList/AccountSwitcherView.swift` (+ its list view + `AccountListViewController`) -- per-row re-login indicator.
- Create `docs/features/session-reauth.md`; modify `docs/features/README.md`.
- Tests: `SpudSnapshotTests/SessionReauthSnapshotTests.swift`.

---

## Task 1: Persisted flag + pure auth-expiry classifier

**Files:**
- Create: `SpudDataKit/Services/Lemmy/AuthExpiry.swift`
- Create: `SpudDataKit/Services/AppDatabase/AccountReauthWrites.swift`
- Modify: `SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift:942` (append after `v36_commentChildCount`)
- Modify: `SpudDataKit/Services/AppDatabase/Records/Account.swift:11-83`
- Modify: `SpudDataKit/Services/AppDatabase/AccountListObservations.swift:16-56,64-106`
- Test: `SpudDataKitTests/AuthExpiryTests.swift`, `SpudDataKitTests/SessionReauthFlagTests.swift`

**Interfaces:**
- Produces (used by Tasks 2-4):
  - `enum AuthExpiry { static func isAuthExpiry(_ error: Error) -> Bool }` -- unwraps both `LemmyApiError` and `LemmyServiceError.apiError`.
  - `AccountRecord.sessionNeedsReauth: Bool` (memberwise-init default `false`).
  - `AppDatabase.setAccountSessionNeedsReauth(keychainId: String, _ needsReauth: Bool) async throws`
  - `AppDatabase.setAccountSessionNeedsReauth(accountId: Int64, _ needsReauth: Bool) async throws`
  - `AppDatabase.accountAnyNeedsReauthSync() -> Bool`
  - `AppDatabase.observeAnyAccountNeedsReauth() -> AsyncStream<Bool>`
  - `AppDatabase.accountPersonNameSync(forKeychainId keychainId: String) -> String?`
  - `AccountListRow.sessionNeedsReauth: Bool` (new stored field + init param, appended last).
- Consumes: `LemmyApiError` (`.unauthorized`, `.serverError(Components.Schemas.ErrorResponse)` whose `.error` is `String`, `.unknownServerError(httpStatusCode:error:)`), `LemmyServiceError.apiError(LemmyApiError)`. Template is `ContentNotFound.swift`.

- [ ] **Step 1: Write the failing classifier test**

Create `SpudDataKitTests/AuthExpiryTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import Testing
@testable import SpudDataKit

@Suite
struct AuthExpiryTests {
    private func errorResponse(_ code: String) -> Components.Schemas.ErrorResponse {
        Components.Schemas.ErrorResponse(error: code)
    }

    @Test func unauthorizedIsAuthExpiry() {
        #expect(AuthExpiry.isAuthExpiry(LemmyApiError.unauthorized(message: nil)))
    }

    @Test func notLoggedInServerErrorIsAuthExpiry() {
        #expect(AuthExpiry.isAuthExpiry(LemmyApiError.serverError(errorResponse("not_logged_in"))))
    }

    @Test func unknownServer401IsAuthExpiry() {
        #expect(AuthExpiry.isAuthExpiry(LemmyApiError.unknownServerError(httpStatusCode: 401, error: nil)))
    }

    @Test func unknownServer403IsNotAuthExpiry() {
        // The whole point: a bare WAF/CDN 403 must never trip the flag.
        #expect(!AuthExpiry.isAuthExpiry(LemmyApiError.unknownServerError(httpStatusCode: 403, error: nil)))
    }

    @Test func rateLimitServerErrorIsNotAuthExpiry() {
        #expect(!AuthExpiry.isAuthExpiry(LemmyApiError.serverError(errorResponse("rate_limit_error"))))
    }

    @Test func networkAndUnknownAreNotAuthExpiry() {
        #expect(!AuthExpiry.isAuthExpiry(LemmyApiError.network(URLError(.timedOut))))
        #expect(!AuthExpiry.isAuthExpiry(LemmyApiError.unknown(URLError(.badURL))))
    }

    @Test func unwrapsLemmyServiceErrorWrapper() {
        // getSiteInfo throws LemmyServiceError(from:), so the classifier must see through .apiError.
        let wrapped = LemmyServiceError.apiError(.unauthorized(message: nil))
        #expect(AuthExpiry.isAuthExpiry(wrapped))
        let wrapped403 = LemmyServiceError.apiError(.unknownServerError(httpStatusCode: 403, error: nil))
        #expect(!AuthExpiry.isAuthExpiry(wrapped403))
    }
}
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `make test-only ONLY=SpudDataKitTests` (or the xcodebuild fallback for a single suite). Expected: build FAILS with "cannot find 'AuthExpiry' in scope".

- [ ] **Step 3: Implement the classifier**

Create `SpudDataKit/Services/Lemmy/AuthExpiry.swift` (mirror `ContentNotFound.swift` style exactly):

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit

/// Recognizes the specific "this account's stored session is no longer valid"
/// rejection, so the passive site refresh and the mutation outbox can flag the
/// account for re-login. This is a NARROW check layered on top of
/// `OutboxFailureClass` (which correctly treats all of these as `.permanent`
/// for rollback) -- it answers only "is this an expired/revoked session", NOT
/// "should this roll back".
///
/// Deliberately EXCLUDES a bare HTTP 403 (`unknownServerError(403)`): that is a
/// WAF/CDN block, not an auth failure, and must never trigger a re-login hint.
public enum AuthExpiry {
    /// Lemmy error codes that mean "you are not authenticated" on a write. Lemmy
    /// returns this (HTTP 400) when a stored JWT is expired/revoked.
    private static let authCodes: Set<String> = ["not_logged_in"]

    /// `true` when `error` is a genuine auth-expiry, unwrapping both the bare
    /// `LemmyApiError` and the `LemmyServiceError.apiError` wrapper.
    public static func isAuthExpiry(_ error: Error) -> Bool {
        switch error {
        case let apiError as LemmyApiError:
            return isAuthExpiry(apiError)
        case let .apiError(apiError) as LemmyServiceError:
            return isAuthExpiry(apiError)
        default:
            return false
        }
    }

    private static func isAuthExpiry(_ apiError: LemmyApiError) -> Bool {
        switch apiError {
        case .unauthorized:
            // HTTP 401 with Lemmy's UnauthorizedResponse.
            return true
        case let .serverError(errorResponse):
            // HTTP 400 carrying a Lemmy error body, e.g. not_logged_in.
            return authCodes.contains(errorResponse.error)
        case let .unknownServerError(httpStatusCode, _):
            // v4 GET /account rejects an invalid token with 401. A bare 403 is
            // WAF/CDN, NOT auth -- excluded here on purpose.
            return httpStatusCode == 401
        case .network, .failedToDeserializeResponse, .unknown:
            return false
        }
    }
}
```

- [ ] **Step 4: Run the classifier test, verify it passes**

Run: `make test-only ONLY=SpudDataKitTests`. Expected: `✔ Test run ... passed`; the 7 `AuthExpiryTests` all green.

- [ ] **Step 5: Commit**

```bash
git add SpudDataKit/Services/Lemmy/AuthExpiry.swift SpudDataKitTests/AuthExpiryTests.swift
git commit -F- <<'EOF'
feat: add AuthExpiry classifier for session-expiry detection

Pure, testable check that distinguishes a genuine expired/revoked JWT
(401 / not_logged_in) from a benign WAF/CDN 403. Layered on top of
OutboxFailureClass; used by the passive site refresh and the outbox to
flag an account for re-login.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011EaJJgwwrWu2oxRdkAZtFY
EOF
```

- [ ] **Step 6: Write the failing migration + flag-write test**

Create `SpudDataKitTests/SessionReauthFlagTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import Testing
@testable import SpudDataKit

@Suite
struct SessionReauthFlagTests {
    /// Inserts a real signed-in account row and returns its keychain id + rowid.
    private func makeSignedInAccount(_ db: AppDatabase) async throws -> (keychainId: String, accountId: Int64) {
        let keychainId = "kc-signed-in"
        let accountId: Int64 = try await db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO instance (actorId, createdAt, updatedAt)
                VALUES ('https://lemmy.example', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
                """)
            let instanceId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO site (instanceId, createdAt, updatedAt)
                VALUES (?, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
                """, arguments: [instanceId])
            let siteId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO account
                    (siteId, accountKeychainId, isDefault, isServiceAccount,
                     isSignedOutAccountType, isEphemeral, createdAt, updatedAt)
                VALUES (?, ?, 1, 0, 0, 0, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
                """, arguments: [siteId, keychainId])
            return db.lastInsertedRowID
        }
        return (keychainId, accountId)
    }

    @Test func migrationAddsFlagDefaultingFalse() async throws {
        let db = try AppDatabase.inMemory()
        let (keychainId, _) = try await makeSignedInAccount(db)
        let record = db.accountRecordSync(forKeychainId: keychainId)
        #expect(record?.sessionNeedsReauth == false)
    }

    @Test func setAndClearByKeychainId() async throws {
        let db = try AppDatabase.inMemory()
        let (keychainId, _) = try await makeSignedInAccount(db)

        try await db.setAccountSessionNeedsReauth(keychainId: keychainId, true)
        #expect(db.accountRecordSync(forKeychainId: keychainId)?.sessionNeedsReauth == true)
        #expect(db.accountAnyNeedsReauthSync())

        try await db.setAccountSessionNeedsReauth(keychainId: keychainId, false)
        #expect(db.accountRecordSync(forKeychainId: keychainId)?.sessionNeedsReauth == false)
        #expect(!db.accountAnyNeedsReauthSync())
    }

    @Test func setByAccountIdMatchesKeychainId() async throws {
        let db = try AppDatabase.inMemory()
        let (keychainId, accountId) = try await makeSignedInAccount(db)
        try await db.setAccountSessionNeedsReauth(accountId: accountId, true)
        #expect(db.accountRecordSync(forKeychainId: keychainId)?.sessionNeedsReauth == true)
    }

    @Test func signedOutAccountNeverFlaggable() async throws {
        let db = try AppDatabase.inMemory()
        let keychainId = "kc-signed-out"
        try await db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO instance (actorId, createdAt, updatedAt)
                VALUES ('https://lemmy.example', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
                """)
            let instanceId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO site (instanceId, createdAt, updatedAt)
                VALUES (?, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
                """, arguments: [instanceId])
            let siteId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO account
                    (siteId, accountKeychainId, isDefault, isServiceAccount,
                     isSignedOutAccountType, isEphemeral, createdAt, updatedAt)
                VALUES (?, ?, 1, 0, 1, 0, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
                """, arguments: [siteId, keychainId])
        }
        // The WHERE guard makes this a no-op, not an error.
        try await db.setAccountSessionNeedsReauth(keychainId: keychainId, true)
        #expect(db.accountRecordSync(forKeychainId: keychainId)?.sessionNeedsReauth == false)
        #expect(!db.accountAnyNeedsReauthSync())
    }
}
```

Note: if `accountRecordSync(forKeychainId:)` does not already exist, the implementer adds a tiny read helper in `AccountReauthWrites.swift` (Step 8) alongside the writes -- `func accountRecordSync(forKeychainId keychainId: String) -> AccountRecord?` fetching the row via `AccountRecord.filter(...)`. Confirm existence first with `grep -rn "func accountRecordSync" SpudDataKit/`; reuse if present.

- [ ] **Step 7: Run the test, verify it fails**

Run: `make test-only ONLY=SpudDataKitTests`. Expected: build FAILS ("value of type 'AccountRecord' has no member 'sessionNeedsReauth'" and "no member 'setAccountSessionNeedsReauth'").

- [ ] **Step 8: Add the migration, the record field, and the writes/reads**

Append to `AppDatabase+Migrations.swift` after the `v36_commentChildCount` block (find the exact insertion point with `grep -n "v36_commentChildCount" SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift`; add the new registration immediately after that migration's closing brace):

```swift
        migrator.registerMigration("v37_sessionNeedsReauth") { db in
            // Per-account flag: the stored JWT was rejected as expired/revoked and
            // the account needs re-login. Only ever set for real signed-in
            // accounts (see AccountReauthWrites' WHERE guard). Self-heals: any
            // successful authed result clears it.
            try db.alter(table: "account") { t in
                t.add(column: "sessionNeedsReauth", .boolean).notNull().defaults(to: false)
            }
        }
```

In `Records/Account.swift`, add the stored property after `showScores` (line 33) and a memberwise-init param defaulting to `false` (so existing call sites keep compiling):

```swift
    // add near line 33, after `public var showScores: Bool?`
    /// The account's stored JWT was rejected as expired/revoked; the UI shows a
    /// quiet re-login hint. Cleared by any successful authed result. Always
    /// `false` for signed-out / service / ephemeral accounts.
    public var sessionNeedsReauth: Bool
```

```swift
    // add to the init parameter list, immediately before `createdAt`:
        sessionNeedsReauth: Bool = false,
    // ...and to the assignment block, before `self.createdAt = createdAt`:
        self.sessionNeedsReauth = sessionNeedsReauth
```

Create `SpudDataKit/Services/AppDatabase/AccountReauthWrites.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import OSLog

private let logger = Logger.appDatabase

public extension AppDatabase {
    /// Sets/clears the re-login flag for the account with `keychainId`. Idempotent.
    /// The `isServiceAccount = 0 AND isSignedOutAccountType = 0` guard makes this a
    /// no-op for accounts that must never carry the flag, rather than an error.
    func setAccountSessionNeedsReauth(keychainId: String, _ needsReauth: Bool) async throws {
        try await writer.write { db in
            try db.execute(sql: """
                UPDATE account
                SET sessionNeedsReauth = ?
                WHERE accountKeychainId = ?
                  AND isServiceAccount = 0
                  AND isSignedOutAccountType = 0
                """, arguments: [needsReauth, keychainId])
        }
    }

    /// Same as above, keyed by the account rowid (the mutation outbox holds an
    /// `accountId`, not a keychain id).
    func setAccountSessionNeedsReauth(accountId: Int64, _ needsReauth: Bool) async throws {
        try await writer.write { db in
            try db.execute(sql: """
                UPDATE account
                SET sessionNeedsReauth = ?
                WHERE id = ?
                  AND isServiceAccount = 0
                  AND isSignedOutAccountType = 0
                """, arguments: [needsReauth, accountId])
        }
    }

    /// One-shot: does ANY real account currently need re-login? Drives the tab dot.
    func accountAnyNeedsReauthSync() -> Bool {
        (try? reader.read { db in
            try Bool.fetchOne(db, sql: """
                SELECT EXISTS(
                    SELECT 1 FROM account
                    WHERE sessionNeedsReauth = 1
                      AND isServiceAccount = 0
                      AND isSignedOutAccountType = 0
                )
                """) ?? false
        }) ?? false
    }

    /// Live "any real account needs re-login" stream for the Account-tab badge.
    func observeAnyAccountNeedsReauth() -> AsyncStream<Bool> {
        let observation = ValueObservation
            .tracking { db -> Bool in
                try Bool.fetchOne(db, sql: """
                    SELECT EXISTS(
                        SELECT 1 FROM account
                        WHERE sessionNeedsReauth = 1
                          AND isServiceAccount = 0
                          AND isSignedOutAccountType = 0
                    )
                    """) ?? false
            }
            .removeDuplicates()

        return AsyncStream { continuation in
            let cancellable = observation.start(in: writer, scheduling: .async(onQueue: .global(qos: .userInitiated))) { error in
                logger.error("AnyAccountNeedsReauth ValueObservation failed: \(String(describing: error), privacy: .public)")
                continuation.finish()
            } onChange: { value in
                continuation.yield(value)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    /// The signed-in account's own `person.name` (username, never display name),
    /// for pre-filling the re-login form. `nil` for signed-out accounts.
    func accountPersonNameSync(forKeychainId keychainId: String) -> String? {
        try? reader.read { db in
            try String.fetchOne(db, sql: """
                SELECT person.name
                FROM account
                JOIN person ON person.id = account.personId
                WHERE account.accountKeychainId = ?
                """, arguments: [keychainId])
        }
    }

    /// Fetches the full account row for `keychainId` (test + flag-read helper).
    /// Reuse an existing equivalent if `grep` finds one.
    func accountRecordSync(forKeychainId keychainId: String) -> AccountRecord? {
        try? reader.read { db in
            try AccountRecord
                .filter(sql: "accountKeychainId = ?", arguments: [keychainId])
                .fetchOne(db)
        }
    }
}
```

Note on `reader`/`writer`: confirm the exact property names with `grep -n "var reader\|var writer\|let reader\|let writer" SpudDataKit/Services/AppDatabase/AppDatabase.swift`. Other observations in this codebase call `observation.start(in: writer, ...)` (see `AccountListObservations.swift:111`) and reads via a reader/writer accessor -- match whatever those existing helpers use. If there is no separate `reader`, use `writer` for reads too (GRDB `DatabasePool`/`DatabaseQueue` reads are legal on the writer).

- [ ] **Step 9: Run the flag test, verify it passes**

Run: `make test-only ONLY=SpudDataKitTests`. Expected: `SessionReauthFlagTests` all green.

- [ ] **Step 10: Surface the flag on `AccountListRow`**

In `AccountListObservations.swift`: add `public let sessionNeedsReauth: Bool` as the LAST stored property (after `avatarUrl`, line 33), add the matching init param (last, after `avatarUrl`) and assignment, add `account.sessionNeedsReauth AS sessionNeedsReauth` to the SELECT (after the `email` column, line 68), and map it in the row builder:

```swift
    // in the SELECT column list, after `account.email AS email,`:
                            account.sessionNeedsReauth AS sessionNeedsReauth,
```

```swift
    // in the AccountListRow(...) construction, after `email: row["email"],`:
                        sessionNeedsReauth: row["sessionNeedsReauth"]
```

- [ ] **Step 11: Add an `AccountListRow` regression assertion**

Append to `SessionReauthFlagTests.swift`:

```swift
    @Test func accountListRowCarriesFlag() async throws {
        let db = try AppDatabase.inMemory()
        let (keychainId, _) = try await makeSignedInAccount(db)
        try await db.setAccountSessionNeedsReauth(keychainId: keychainId, true)

        var iterator = db.observeAccountListRows().makeAsyncIterator()
        let rows = await iterator.next()
        let row = rows?.first { $0.accountKeychainId == keychainId }
        #expect(row?.sessionNeedsReauth == true)
    }
```

- [ ] **Step 12: Format, run the full data suite, verify green**

Run: `mint run swiftformat SpudDataKit/Services/Lemmy/AuthExpiry.swift SpudDataKit/Services/AppDatabase/AccountReauthWrites.swift SpudDataKit/Services/AppDatabase/Records/Account.swift SpudDataKit/Services/AppDatabase/AccountListObservations.swift SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift SpudDataKitTests/SessionReauthFlagTests.swift`
Then: `make test-only ONLY=SpudDataKitTests`. Expected: whole suite green.

- [ ] **Step 13: Commit**

```bash
git add SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift \
        SpudDataKit/Services/AppDatabase/Records/Account.swift \
        SpudDataKit/Services/AppDatabase/AccountReauthWrites.swift \
        SpudDataKit/Services/AppDatabase/AccountListObservations.swift \
        SpudDataKitTests/SessionReauthFlagTests.swift
git commit -F- <<'EOF'
feat: persist per-account sessionNeedsReauth flag

v37 migration adds account.sessionNeedsReauth; AccountRecord and
AccountListRow carry it. Idempotent set/clear writes (by keychain id and
by account id) guarded to real signed-in accounts, plus a live
"any account needs re-login" stream for the tab badge and a username
read for pre-filling the re-login form.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011EaJJgwwrWu2oxRdkAZtFY
EOF
```

---

## Task 2: Detection wiring (passive + write-side)

**Files:**
- Modify: `SpudDataKit/Services/Lemmy/LemmyService.swift:1247-1313` (`getSiteInfo()`)
- Modify: `SpudDataKit/Services/Outbox/OutboxService.swift:18-23` (`OutboxFailure`), `:228-281` (`.permanent` path)
- Test: extend `SpudDataKitTests/SessionReauthFlagTests.swift`

**Interfaces:**
- Consumes: `AuthExpiry.isAuthExpiry(_:)`, `AppDatabase.setAccountSessionNeedsReauth(keychainId:_:)` + `(accountId:_:)` (Task 1).
- Produces: `OutboxFailure.isAuthExpiry: Bool` (new field, appended last) -- consumed by `MainWindow` in Task 4.

Detection rules (from spec 2.2/2.3):
- Passive `getSiteInfo()`, signed-in only: fetch SUCCESS with `myUser != nil` -> clear; SUCCESS with `myUser == nil` (v3 token rejected) -> set; THROWN error that `AuthExpiry.isAuthExpiry` -> set (v4 401), then re-throw unchanged. A thrown WAF 403 -> `isAuthExpiry` false -> NOT set.
- `accountIdentifierForLogging` is the plain keychain id (it is passed unhashed to `upsertAccount(keychainId:)`; only the logger masks it). Use it as the keychain id for the flag writes.

- [ ] **Step 1: Write the failing passive-trigger tests**

Append to `SessionReauthFlagTests.swift`. Reuse the existing `getSiteInfo` stub-transport harness if one exists (`grep -rn "getSiteInfo\|SiteWithMyUser\|ClientTransport\|makeApi" SpudDataKitTests/ | grep -i site`); otherwise drive `LemmyService.getSiteInfo()` through the same stub-`ClientTransport` pattern `LemmyServiceContentNotFoundTests` uses. Cover exactly three cases against a real signed-in account row:

```swift
    // Pseudocode contract -- fill in with the project's LemmyService test harness.
    // Case A: signed-in v3 getSite SUCCEEDS but my_user is absent -> flag set.
    //   stub GET /site -> 200 GetSiteResponse WITHOUT my_user
    //   try await service.getSiteInfo()
    //   #expect(db.accountRecordSync(forKeychainId: kc)?.sessionNeedsReauth == true)
    //
    // Case B: signed-in getSite SUCCEEDS with my_user present -> flag CLEARED.
    //   pre-set the flag true, stub GET /site -> 200 WITH my_user
    //   try await service.getSiteInfo()
    //   #expect(db.accountRecordSync(forKeychainId: kc)?.sessionNeedsReauth == false)
    //
    // Case C: signed-in getSite throws a WAF 403 -> flag UNCHANGED (stays false).
    //   stub -> HTTP 403 empty body (-> unknownServerError(403))
    //   await #expect(throws: (any Error).self) { try await service.getSiteInfo() }
    //   #expect(db.accountRecordSync(forKeychainId: kc)?.sessionNeedsReauth == false)
```

If constructing a `LemmyService` bound to a specific account in a unit test is impractical with the current harness, implement Cases A-C as an integration-style test using the existing `LemmyService` test fixture; do NOT weaken the assertions. If genuinely blocked on the harness, report BLOCKED with the specific missing seam rather than skipping a case.

- [ ] **Step 2: Run, verify it fails**

Run: `make test-only ONLY=SpudDataKitTests`. Expected: Cases A and C fail (flag not written) -- proving the wiring is absent.

- [ ] **Step 3: Wire the passive trigger in `getSiteInfo()`**

In `LemmyService.swift`, inside the `catch` of the fetch `do` (before `throw LemmyServiceError(from: error)`, after the `diagnostics.record(...)` call at ~1288), add:

```swift
            // A genuine auth-expiry (v4 GET /account 401) flags the account for
            // re-login. A WAF 403 is NOT auth (AuthExpiry excludes it), so this
            // never fires on the benign background 403. Signed-out accounts have
            // no session to expire.
            if !accountIsSignedOut, AuthExpiry.isAuthExpiry(error) {
                try? await appDatabase.setAccountSessionNeedsReauth(
                    keychainId: accountIdentifierForLogging,
                    true
                )
            }
```

And in the SUCCESS region, after the upsert `do { ... } catch { logger.error(...) }` block (after line ~1310, before `return siteInfo`), add:

```swift
        // Self-heal: a signed-in refresh that returned my_user proves the token
        // is good -> clear any stale flag. A signed-in refresh that SUCCEEDED but
        // returned no my_user (v3 token rejected) -> set it. Signed-out accounts
        // never carry the flag.
        if !accountIsSignedOut {
            try? await appDatabase.setAccountSessionNeedsReauth(
                keychainId: accountIdentifierForLogging,
                myUser == nil
            )
        }
```

- [ ] **Step 4: Run passive tests, verify they pass**

Run: `make test-only ONLY=SpudDataKitTests`. Expected: Cases A, B, C green.

- [ ] **Step 5: Write the failing write-side test**

Append a test asserting the outbox permanent path flags on an auth error and tags the failure. Reuse the `OutboxService` test harness (`grep -rn "OutboxService\|OutboxFailure\|emitFailure\|drainOnce" SpudDataKitTests/`). Contract:

```swift
    // Given a signed-in account and an OutboxService whose performer throws
    //   LemmyApiError.unauthorized(message: nil) (a permanent, auth error):
    //   enqueue a vote op, drainOnce()
    //   -> the emitted OutboxFailure.isAuthExpiry == true
    //   -> db.accountRecordSync(forKeychainId: kc)?.sessionNeedsReauth == true
    //
    // And given the performer throws unknownServerError(403) (permanent, NOT auth):
    //   -> the emitted OutboxFailure.isAuthExpiry == false
    //   -> the flag stays false
```

- [ ] **Step 6: Run, verify it fails**

Run: `make test-only ONLY=SpudDataKitTests`. Expected: build fails ("no member 'isAuthExpiry'") then, once the field is added but unwired, the flag assertion fails.

- [ ] **Step 7: Add `isAuthExpiry` to `OutboxFailure` and wire the trigger**

In `OutboxService.swift`, extend the struct (append the field last so ordering is stable):

```swift
public struct OutboxFailure: Sendable, Equatable {
    public let entityType: OutboxEntityType
    public let entityServerId: Int64
    public let kind: OutboxKind
    public let reason: OutboxFailureReason
    /// True when the permanent failure was a genuine expired/revoked session
    /// (not a WAF 403). Drives MainWindow's "Session expired" re-login toast.
    public let isAuthExpiry: Bool
}
```

In the `.permanent` branch (~228-281), before the `emitFailure(...)` call, compute and apply the flag:

```swift
                    // Flag the account for re-login when this permanent failure is
                    // a genuine auth-expiry. AuthExpiry excludes a bare 403, so a
                    // WAF-blocked write never trips it.
                    let isAuthExpiry = AuthExpiry.isAuthExpiry(error)
                    if isAuthExpiry {
                        try? await appDatabase.setAccountSessionNeedsReauth(accountId: accountId, true)
                    }
```

Then thread it into the constructed failure:

```swift
                    emitFailure(OutboxFailure(
                        entityType: op.entityType,
                        entityServerId: op.entityServerId,
                        kind: op.kind,
                        reason: reason,
                        isAuthExpiry: isAuthExpiry
                    ))
```

Update every OTHER `OutboxFailure(...)` construction (tests + any fixture) to pass `isAuthExpiry:` -- find them with `grep -rn "OutboxFailure(" SpudDataKit SpudDataKitTests Spud`.

- [ ] **Step 8: Run write-side tests, verify they pass**

Run: `make test-only ONLY=SpudDataKitTests`. Expected: write-side cases green.

- [ ] **Step 9: Format + full data suite verify**

Run: `mint run swiftformat SpudDataKit/Services/Lemmy/LemmyService.swift SpudDataKit/Services/Outbox/OutboxService.swift SpudDataKitTests/SessionReauthFlagTests.swift`
Then: `make test-only ONLY=SpudDataKitTests`. Expected: green.

- [ ] **Step 10: Commit**

```bash
git add SpudDataKit/Services/Lemmy/LemmyService.swift \
        SpudDataKit/Services/Outbox/OutboxService.swift \
        SpudDataKitTests/SessionReauthFlagTests.swift
git commit -F- <<'EOF'
feat: detect session expiry on site refresh and outbox failure

getSiteInfo self-heals the flag on every signed-in refresh (set when a
v3 getSite succeeds with no my_user or a v4 getMyUser 401s; cleared when
my_user is present). The mutation outbox flags the account on a permanent
auth failure and tags OutboxFailure.isAuthExpiry. A WAF 403 trips neither.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011EaJJgwwrWu2oxRdkAZtFY
EOF
```

---

## Task 3: In-place re-authentication

**Files:**
- Modify: `SpudDataKit/Services/Account/AccountService.swift:17-160` (protocol), `:655-705` (`login`, as reference), `:788-803` (`storeSignedInCredential`, as reference), `:929` (`writeCredential`)
- Modify: `Spud/Scenes/Account/Login/LoginViewModel.swift:38-44,81-147`
- Modify: `Spud/Scenes/Account/Login/LoginViewController.swift:299-314,321-374,428-492`
- Create: `Spud/Scenes/Account/AccountReauthLauncher.swift`
- Test: `SpudDataKitTests/AccountReauthenticateTests.swift`

**Interfaces:**
- Consumes: `AccountService.instanceActorId(forAccountKeychainId:) -> InstanceActorId?`, `writeCredential(_:forKeychainId:)`, `fetchInitialSiteInfo(forAccountKeychainId:)`, `preflightHomeConnection(host:)`, `makeApi(_:_:_:)`, `AppDatabase.setAccountSessionNeedsReauth(keychainId:_:)`, `AppDatabase.accountPersonNameSync(forKeychainId:)`, `SiteListRow.forTypedInstance(_:)`, `AccountServiceLoginError`.
- Produces (used by Task 4):
  - `AccountServiceType.reauthenticate(keychainId: String, username: String, password: String, totp2faToken: String?) async throws`
  - `AccountServiceType.username(forAccountKeychainId keychainId: String) -> String?`
  - `LoginViewModel` gains `init(row:initialUsername:reauthTarget:dependencies:)` (defaults keep old callers working); `struct LoginViewModel.ReauthTarget { let keychainId: String }`.
  - `LoginViewController.init(row:initialUsername:reauthTarget:dependencies:)` (defaults keep old callers working).
  - `AccountReauthLauncher.present(forAccountKeychainId:from:accountService:dependencies:)` (app-level).

Key rule: re-auth reuses the EXISTING keychain id -- it does NOT mint a new UUID, call `ensureAccount`, or `setDefaultAccount`. That is the entire difference from `login` (which duplicates today).

- [ ] **Step 1: Write the failing reauthenticate test**

Create `SpudDataKitTests/AccountReauthenticateTests.swift`. Reuse the `AccountService` test harness (in-memory `CredentialStore` + injected api) that the existing login tests use -- find it with `grep -rln "storeSignedInCredential\|reauthenticate\|CredentialStore\|AccountServiceLoginError\|func login" SpudDataKitTests/`. Assert:

```swift
    // Given a signed-in account with keychainId KC and a stored (stale) credential,
    // and the account flagged sessionNeedsReauth == true:
    //   try await accountService.reauthenticate(keychainId: KC,
    //       username: "alice", password: "pw", totp2faToken: nil)
    // Then:
    //   - the account COUNT is unchanged (no duplicate row)  <-- the core assertion
    //   - the same KC now holds the NEW jwt (credentialStore.credential(forKeychainId: KC) updated)
    //   - db.accountRecordSync(forKeychainId: KC)?.sessionNeedsReauth == false
    //   - the account's siteId / personId / isDefault are unchanged (identity preserved)
    //
    // And a wrong-password reauthenticate throws AccountServiceLoginError.invalidLogin
    //   and does NOT clear the flag and does NOT change the stored credential.
```

Model the assertions on the existing login test's account-count / credential-store checks. If the login harness stubs the network `api.login(...)`, stub it to return a `LoginResponse` with a fresh jwt for the success case and throw the invalid-login error for the failure case.

- [ ] **Step 2: Run, verify it fails**

Run: `make test-only ONLY=SpudDataKitTests`. Expected: build fails ("no member 'reauthenticate'").

- [ ] **Step 3: Implement `reauthenticate` + `username(forAccountKeychainId:)`**

Add to the `AccountServiceType` protocol (after `login(...)`, near line 61):

```swift
    /// Re-authenticates an EXISTING account in place: logs in on the account's
    /// own instance and writes the new token to the account's existing keychain
    /// id -- no duplicate account, no identity change. Clears sessionNeedsReauth
    /// on success. 2FA behaves exactly as `login`.
    func reauthenticate(
        keychainId: String,
        username: String,
        password: String,
        totp2faToken: String?
    ) async throws

    /// The account's own username (person.name), for pre-filling the re-login
    /// form. `nil` for signed-out accounts or before the person row resolves.
    func username(forAccountKeychainId keychainId: String) -> String?
```

Implement in `AccountService` (near `login`, ~705). Reuse `login`'s error mapping verbatim:

```swift
    public func reauthenticate(
        keychainId: String,
        username: String,
        password: String,
        totp2faToken: String?
    ) async throws {
        guard let instance = instanceActorId(forAccountKeychainId: keychainId),
              let url = instance.url
        else {
            throw AccountServiceLoginError.missingJwt
        }

        try await preflightHomeConnection(host: instance.host)

        // Same unauthenticated v3 login call as `login` (version isn't known until
        // getSite runs; login predates that).
        let api = makeApi(url, nil, .v3)

        let response: Lemmy.LoginResponse
        do {
            response = try await api.login(
                usernameOrEmail: username,
                password: password,
                totp2faToken: totp2faToken
            )
        } catch {
            let error = AccountServiceLoginError(from: error)
            if case .invalidLogin = error {
                throw error
            }
            logger.error("""
                Re-auth failed. instance=\(instance.actorId, privacy: .public). \
                username=\(username, privacy: .sensitive(mask: .hash))
                \(String(describing: error), privacy: .public)
                """)
            throw error
        }

        guard let jwt = response.jwt else {
            throw AccountServiceLoginError.missingJwt
        }

        // Reuse the EXISTING keychain id -- no ensureAccount, no new UUID, no
        // setDefaultAccount. This is what makes re-login in place, not a duplicate.
        writeCredential(LemmyCredential(jwt: jwt), forKeychainId: keychainId)
        try? await appDatabase.setAccountSessionNeedsReauth(keychainId: keychainId, false)
        // Refresh site / my-user now (also clears the flag via the passive path).
        fetchInitialSiteInfo(forAccountKeychainId: keychainId)
    }

    public func username(forAccountKeychainId keychainId: String) -> String? {
        appDatabase.accountPersonNameSync(forKeychainId: keychainId)
    }
```

Note: `writeCredential` is currently `private` (line 929). Since `reauthenticate` is a method ON `AccountService`, it can call the private method -- no visibility change needed. Confirm both are in the same type/extension scope; if `reauthenticate` lands in a different extension that can't see the `private`, relax `writeCredential` to `fileprivate`/internal minimally, or place `reauthenticate` in the same extension as `login`.

- [ ] **Step 4: Run reauthenticate tests, verify they pass**

Run: `make test-only ONLY=SpudDataKitTests`. Expected: no-duplicate + credential-updated + flag-cleared + wrong-password cases green. Also update any `AccountServiceType` test double / mock to implement the two new protocol methods (find with `grep -rln "AccountServiceType" SpudDataKitTests SpudTests`) -- a missing method is a compile error in the test target.

- [ ] **Step 5: Commit the service layer**

```bash
git add SpudDataKit/Services/Account/AccountService.swift SpudDataKitTests/AccountReauthenticateTests.swift
git commit -F- <<'EOF'
feat: add AccountService.reauthenticate for in-place re-login

Logs in on the account's own instance and writes the new token to the
existing keychain id -- no duplicate account, identity preserved -- then
clears sessionNeedsReauth and refreshes site/my-user. 2FA and error
mapping mirror login. Adds username(forAccountKeychainId:) for pre-fill.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011EaJJgwwrWu2oxRdkAZtFY
EOF
```

- [ ] **Step 6: Add re-auth mode to `LoginViewModel`**

In `LoginViewModel.swift`, add the target type + init params (defaults preserve existing callers), pre-fill `username`, and branch `login()`:

```swift
    /// When set, the login screen re-authenticates an EXISTING account rather
    /// than creating a new one. Carries the account's keychain id so a successful
    /// submit routes to `reauthenticate` (which reuses the keychain id) instead
    /// of `login` (which would duplicate the account).
    struct ReauthTarget: Equatable {
        let keychainId: String
    }

    let reauthTarget: ReauthTarget?
```

```swift
    init(
        row: SiteListRow,
        initialUsername: String = "",
        reauthTarget: ReauthTarget? = nil,
        dependencies: Dependencies
    ) {
        self.row = row
        self.reauthTarget = reauthTarget
        self.dependencies = (own: dependencies, nested: dependencies)
        instanceName = row.hostname
        username = initialUsername
        // ... existing icon setup unchanged ...
    }
```

In `login()`, replace the single `accountService.login(...)` call with a branch (everything else -- 2FA, error handling, `loggedIn` -- unchanged):

```swift
        do {
            if let reauthTarget {
                try await accountService.reauthenticate(
                    keychainId: reauthTarget.keychainId,
                    username: username,
                    password: password,
                    totp2faToken: totp2faToken
                )
            } else {
                try await accountService.login(
                    atInstance: row.instance,
                    username: username,
                    password: password,
                    totp2faToken: totp2faToken
                )
            }
            loggedIn = true
        } catch let error as PlatformUnsupportedError {
        // ... rest unchanged ...
```

- [ ] **Step 7: Add re-auth mode to `LoginViewController`**

In `LoginViewController.swift`, add the two params to `init` (defaults preserve the four existing call sites), forward them to the view model, pre-fill the field, and re-title when re-authenticating:

```swift
    init(
        row: SiteListRow,
        initialUsername: String = "",
        reauthTarget: LoginViewModel.ReauthTarget? = nil,
        dependencies: Dependencies
    ) {
        self.dependencies = (own: dependencies, nested: dependencies)
        viewModel = LoginViewModel(
            row: row,
            initialUsername: initialUsername,
            reauthTarget: reauthTarget,
            dependencies: self.dependencies.nested
        )
        super.init(nibName: nil, bundle: nil)
        setup()
        bindViewModel()
    }
```

In `setup()`, after setting the title (line 328), override it for re-auth, and disable the anonymous/register affordances that make no sense when re-logging in:

```swift
        if viewModel.reauthTarget != nil {
            navigationItem.title = NSLocalizedString("Log back in", comment: "Re-login screen title")
        }
```

In `bindViewModel()`, pre-fill the username field from the view model (it was set from `initialUsername`):

```swift
        usernameField.textField.text = viewModel.username
```

For re-auth mode, hide the "browse anonymously" / "create an account" paths (re-login is not a place to make a new account). Add near the end of `setup()`:

```swift
        if viewModel.reauthTarget != nil {
            anonymousButton.isHidden = true
            orDividerStackView.isHidden = true
            registerLineLabel.isHidden = true
        }
```

- [ ] **Step 8: Create the launch helper**

Create `Spud/Scenes/Account/AccountReauthLauncher.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import UIKit

/// Presents the login screen in re-auth mode for an existing account: the
/// account's instance and username are pre-filled, the password is empty, and a
/// successful submit re-authenticates in place (no duplicate account). Every
/// session-expired hint surface routes here.
@MainActor
enum AccountReauthLauncher {
    static func present(
        forAccountKeychainId keychainId: String,
        from presenter: UIViewController,
        accountService: AccountServiceType,
        dependencies: LoginViewController.Dependencies
    ) {
        guard let instance = accountService.instanceActorId(forAccountKeychainId: keychainId) else {
            return
        }
        let row = SiteListRow.forTypedInstance(instance)
        let username = accountService.username(forAccountKeychainId: keychainId) ?? ""
        let loginViewController = LoginViewController(
            row: row,
            initialUsername: username,
            reauthTarget: .init(keychainId: keychainId),
            dependencies: dependencies
        )
        let navigationController = UINavigationController(rootViewController: loginViewController)
        presenter.present(navigationController, animated: true)
    }
}
```

- [ ] **Step 9: Regenerate the project + build (new file)**

Run: `make project` (XcodeGen picks up `AccountReauthLauncher.swift`). Then `make build`. Expected: builds clean.

- [ ] **Step 10: Format + build test targets**

Run: `mint run swiftformat Spud/Scenes/Account/Login/LoginViewModel.swift Spud/Scenes/Account/Login/LoginViewController.swift Spud/Scenes/Account/AccountReauthLauncher.swift`
Then: `make test` (builds the whole plan; catches any test-double gaps from the protocol additions). Expected: green.

- [ ] **Step 11: Commit the UI plumbing**

```bash
git add Spud/Scenes/Account/Login/LoginViewModel.swift \
        Spud/Scenes/Account/Login/LoginViewController.swift \
        Spud/Scenes/Account/AccountReauthLauncher.swift
git commit -F- <<'EOF'
feat: re-auth mode for the login screen + launch helper

LoginViewModel/LoginViewController gain an optional pre-filled username
and a re-auth target; in re-auth mode a successful submit calls
reauthenticate (in place) and the create-account / anonymous affordances
are hidden. AccountReauthLauncher builds this from an account keychain id.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011EaJJgwwrWu2oxRdkAZtFY
EOF
```

---

## Task 4: Surfacing + docs

**Files:**
- Modify: `Spud/Scenes/MainWindow/MainWindow.swift:63` (accountTabIndex), `:386-403` (badge observation), `:428-450` (toast)
- Modify: `Spud/Scenes/Account/AccountViewModel.swift:33-56,110-123`
- Modify: `Spud/Scenes/Account/AccountView.swift:15-92`
- Modify: `Spud/Scenes/Account/AccountViewController.swift:170-186`
- Modify: `Spud/Scenes/Account/AccountList/AccountSwitcherView.swift:140-159,165-210` (+ its list view + `AccountListViewController` callback wiring)
- Create: `docs/features/session-reauth.md`
- Modify: `docs/features/README.md`
- Test: `SpudSnapshotTests/SessionReauthSnapshotTests.swift`

**Interfaces:**
- Consumes: `AppDatabase.observeAnyAccountNeedsReauth()`, `AccountListRow.sessionNeedsReauth`, `AccountRecord.sessionNeedsReauth`, `OutboxFailure.isAuthExpiry`, `AccountReauthLauncher.present(...)` (Tasks 1-3), `ToastPresenter.shared.show(_:actionTitle:in:duration:action:)`.

Four surfaces, all routing to `AccountReauthLauncher.present(...)`:
1. Account-tab "!" dot when ANY real account is flagged.
2. Account-screen prominent re-login section for the active account.
3. Account-switcher per-row re-login affordance.
4. In-the-moment interactive toast on a blocked action.

- [ ] **Step 1: Account-tab dot in `MainWindow`**

Add an observation task mirroring `startObservingUnreadCount()` (line 386) and an `applyReauthBadge`. Start it wherever `startObservingUnreadCount()` is started. `appDatabase` is available in `MainWindow` (used at line 216). Add:

```swift
    private var reauthBadgeObservationTask: Task<Void, Never>?

    private func startObservingReauthBadge() {
        reauthBadgeObservationTask?.cancel()
        let appDatabase = appDatabase
        reauthBadgeObservationTask = Task { @MainActor [weak self] in
            for await needsReauth in appDatabase.observeAnyAccountNeedsReauth() {
                if Task.isCancelled { break }
                self?.applyReauthBadge(needsReauth)
            }
        }
    }

    private func applyReauthBadge(_ needsReauth: Bool) {
        guard
            let items = tabBarController.tabBar.items,
            items.indices.contains(Self.accountTabIndex)
        else { return }
        items[Self.accountTabIndex].badgeValue = needsReauth ? "!" : nil
    }
```

Call `startObservingReauthBadge()` next to the existing `startObservingUnreadCount()` call, and cancel `reauthBadgeObservationTask` wherever `unreadCountObservationTask` is cancelled (find both with `grep -n "startObservingUnreadCount\|unreadCountObservationTask?.cancel" Spud/Scenes/MainWindow/MainWindow.swift`).

- [ ] **Step 2: Auth-expiry toast branch in `MainWindow`**

In `presentOutboxFailureToast(_:)` (line 428), branch on `isAuthExpiry` FIRST (it takes priority over `reason`/`kind`) and present an interactive toast that routes to re-auth:

```swift
    private func presentOutboxFailureToast(_ failure: OutboxFailure) {
        if failure.isAuthExpiry {
            let keychainId = currentDefaultAccountKeychainId
            ToastPresenter.shared.show(
                NSLocalizedString("Session expired", comment: "Toast when an action failed because the session expired"),
                actionTitle: NSLocalizedString("Re-login", comment: "Toast action to re-authenticate the account"),
                in: self
            ) { [weak self] in
                guard let self, let keychainId else { return }
                AccountReauthLauncher.present(
                    forAccountKeychainId: keychainId,
                    from: topmostPresenter(),
                    accountService: accountService,
                    dependencies: dependencies.nested
                )
            }
            return
        }
        // ... existing reason/kind switch unchanged ...
    }
```

`currentDefaultAccountKeychainId` is already referenced in this file (line 422). For `topmostPresenter()`: use the existing pattern MainWindow uses to present modals (e.g. the selected tab's nav controller). If a helper exists, reuse it; otherwise present from `tabBarController.selectedViewController ?? self`. Confirm `dependencies.nested` satisfies `LoginViewController.Dependencies` (MainWindow already builds `LoginViewController(row:dependencies: dependencies.nested)` at line 225, so it does).

- [ ] **Step 3: Account-screen re-login row -- view model**

In `AccountViewModel.swift`, add an observed flag fed by the already-observed default account record:

```swift
    /// True when the active account's stored session expired and needs re-login.
    private(set) var sessionNeedsReauth: Bool = false
```

In `apply(record:)` (line 110), set it:

```swift
        sessionNeedsReauth = record.sessionNeedsReauth && !record.isSignedOutAccountType
```

- [ ] **Step 4: Account-screen re-login row -- view + controller**

In `AccountView.swift`, add an `onReauth` callback and a prominent top section shown only when flagged:

```swift
    let onReauth: () -> Void
```

At the top of the `List` body, before the profile `Section` (line 30), insert:

```swift
            if viewModel.sessionNeedsReauth {
                Section {
                    Button(action: onReauth) {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(NSLocalizedString("Session expired", comment: "Account re-login row title"))
                                    .font(.headline)
                                    .foregroundStyle(Color(.label))
                                Text(NSLocalizedString("Tap to log back in", comment: "Account re-login row subtitle"))
                                    .font(.subheadline)
                                    .foregroundStyle(Color(.secondaryLabel))
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color(.tertiaryLabel))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text(NSLocalizedString("Session expired, log back in", comment: "Account re-login row accessibility label")))
                    .accessibilityAddTraits(.isButton)
                }
            }
```

In `AccountViewController.swift`, wire `onReauth` in the `AccountView(...)` construction (line 170) to the launcher:

```swift
            onReauth: { [weak self] in
                guard let self else { return }
                AccountReauthLauncher.present(
                    forAccountKeychainId: keychainId,
                    from: self,
                    accountService: accountService,
                    dependencies: dependencies.nested
                )
            },
```

Confirm `dependencies.nested` conforms to `LoginViewController.Dependencies` from `AccountViewController` (it already constructs login-flow VCs via `dependencies.nested`); if the typealias differs, pass the dependency set the existing `openLoginFlow()`/`SiteListViewController` uses.

- [ ] **Step 5: Account-switcher per-row re-login affordance**

In `AccountSwitcherView.swift`, thread a new `onReauth: (String) -> Void` callback from the switcher view down to `accountRow(_:)`, and in `AccountSwitcherAccountRow` show a compact "Re-login" affordance when `row.sessionNeedsReauth` (keyed off the new `AccountListRow` field). Add to the row's trailing area (before/around the `RadioCheck`, line 189):

```swift
                if row.sessionNeedsReauth {
                    Button {
                        onReauth()
                    } label: {
                        Text(NSLocalizedString("Re-login", comment: "Account switcher per-account re-login affordance"))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(NSLocalizedString("Re-login", comment: "Account switcher re-login affordance")))
                }
```

`AccountSwitcherAccountRow` needs an `onReauth: () -> Void` param; pass it from `accountRow(_:)`:

```swift
        AccountSwitcherAccountRow(row: row, accent: accent) {
            onSelect(row.accountKeychainId)
        } onReauth: {
            onReauth(row.accountKeychainId)
        }
```

Wire the new `onReauth` callback through `AccountListViewController` (the host that constructs `AccountSwitcherView` -- find with `grep -rn "AccountSwitcherView(" Spud/`) to `AccountReauthLauncher.present(forAccountKeychainId: $0, from: self, accountService:, dependencies:)`.

- [ ] **Step 6: Regenerate + build**

Run: `make project` (new `AccountReauthLauncher.swift` was added in Task 3; no new files here, but run it if any were added). Then `make build`. Expected: clean.

- [ ] **Step 7: Snapshot tests for the two SwiftUI surfaces**

Create `SpudSnapshotTests/SessionReauthSnapshotTests.swift`. Follow the existing Account snapshot pattern (`grep -rln "AccountView\|AccountSwitcher" SpudSnapshotTests/`; reuse `SnapshotDependencies` / `SnapshotPreferences.ephemeral()` / `.image(on: .deterministicPhone)`). Record:
- `AccountView` with `viewModel.sessionNeedsReauth == true` (the re-login section visible) and `== false` (absent).
- `AccountSwitcherView` with one flagged row and one clean row (the per-row "Re-login" affordance visible on exactly one).

First run records missing refs and fails; rerun verifies. Record on the reference device only.

- [ ] **Step 8: Run snapshots on the reference device**

Run: `make snapshot` (fails fast if the booted sim is not iPhone 17 Pro / iOS 26.3.x). First run records + fails; run again to verify. `git add` ONLY the explicit new refs under `SpudSnapshotTests/__Snapshots__/SessionReauthSnapshotTests/` (annex-tracked -- do not `git add -A`).

- [ ] **Step 9: Feature docs**

Create `docs/features/session-reauth.md` at PM level following `docs/features/_TEMPLATE.md`. Include Given/When/Then scenarios: (a) a signed-in session expires -> the account is flagged -> the Account tab shows a "!" dot, the Account screen shows a "Session expired" row, and the switcher marks that account; (b) a blocked action (vote/comment) with an expired session -> a "Session expired -- Re-login" toast -> tap -> pre-filled re-login -> on success the flag clears everywhere; (c) a WAF/CDN 403 -> NO hint ever appears; (d) re-login reuses the same account (no duplicate). Set `Status:` accurately (e.g. `Implemented (pending on-device validation)`). `Surfaces:` = union of the scenario tags. No `.swift` links.

Update `docs/features/README.md`: add a row to the capability table AND an entry in the "Feature coverage by area" map (both sections -- they drift independently). Reconcile the adjacent accounts/login docs (`grep -rln "log in\|login\|account" docs/features/`) so nothing contradicts the new re-login behavior.

- [ ] **Step 10: Format + full verify**

Run: `mint run swiftformat Spud/Scenes/MainWindow/MainWindow.swift Spud/Scenes/Account/AccountViewModel.swift Spud/Scenes/Account/AccountView.swift Spud/Scenes/Account/AccountViewController.swift Spud/Scenes/Account/AccountList/AccountSwitcherView.swift`
Then: `make test`. Expected: whole plan green (unit + UI). Snapshots via `make snapshot` already verified in Step 8.

- [ ] **Step 11: Commit**

```bash
git add Spud/Scenes/MainWindow/MainWindow.swift \
        Spud/Scenes/Account/AccountViewModel.swift \
        Spud/Scenes/Account/AccountView.swift \
        Spud/Scenes/Account/AccountViewController.swift \
        Spud/Scenes/Account/AccountList/AccountSwitcherView.swift \
        docs/features/session-reauth.md docs/features/README.md \
        SpudSnapshotTests/SessionReauthSnapshotTests.swift \
        SpudSnapshotTests/__Snapshots__/SessionReauthSnapshotTests
# also stage the AccountListViewController file actually modified in Step 5:
#   git add Spud/Scenes/Account/AccountList/<AccountListViewController.swift>
git commit -F- <<'EOF'
feat: surface the session-expired re-login hint

Account-tab "!" dot, a prominent Account-screen re-login row, a per-row
re-login affordance in the account switcher, and an in-the-moment
"Session expired -- Re-login" toast on a blocked action. All route to the
in-place re-auth launcher. A WAF 403 surfaces nothing. Adds feature docs.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011EaJJgwwrWu2oxRdkAZtFY
EOF
```

---

## Self-Review

**Spec coverage:**
- 2.1 Classifier -> Task 1 (`AuthExpiry`), tests cover 401/not_logged_in/unknown-401 = auth; 403/rate_limit/network/unknown = not.
- 2.2 Write-side trigger -> Task 2 (outbox `.permanent` classify + flag + `OutboxFailure.isAuthExpiry`); rollback unchanged.
- 2.3 Passive trigger -> Task 2 (`getSiteInfo` set on v3 nil-my_user / v4 401, clear on my_user present, WAF 403 excluded).
- 2.4 Self-heal -> Task 2 (clear on any successful authed getSite) + Task 3 (explicit clear on re-login) + Task 1 (`setAccountSessionNeedsReauth`).
- 3.1 Migration + record + AccountListRow + AppDatabase writes -> Task 1.
- 3.2 In-place re-auth (no duplicate) -> Task 3 (`reauthenticate` reuses keychain id; test asserts count unchanged).
- 3.3 Pre-fillable re-auth-mode login + launch helper -> Task 3.
- 4 Surfacing (tab dot, Account row, switcher indicator, toast) -> Task 4.
- 5 Out of scope: no token auto-refresh, no consecutive-failure counter, no why-died distinction, no OutboxFailureClass change, no signed-out give-up change -- none added.
- 6 Testing: classifier unit (T1), flag transitions (T1), passive trigger (T2), write-side (T2), reauthenticate no-duplicate/clear/wrong-password (T3), UI snapshot (T4). All present.
- 8 Docs -> Task 4 Step 9.

**Placeholder scan:** The only intentionally-prose steps are Task 2 Step 1 and Task 3 Step 1 (test bodies written as explicit contracts because they must bind to the project's existing `LemmyService`/`OutboxService`/`AccountService` test harnesses, which the implementer must locate with the given `grep`s rather than have me invent a mock signature that may not match). Every production-code step carries complete code. No "TBD"/"handle errors"/"similar to Task N".

**Type consistency:** `sessionNeedsReauth: Bool` is spelled identically on `AccountRecord`, `AccountListRow`, `AccountViewModel`, and in every SQL column. `setAccountSessionNeedsReauth` has two overloads (keychainId / accountId), both used as declared. `AuthExpiry.isAuthExpiry(_:)`, `OutboxFailure.isAuthExpiry`, `reauthenticate(keychainId:username:password:totp2faToken:)`, `username(forAccountKeychainId:)`, `LoginViewModel.ReauthTarget`, and `AccountReauthLauncher.present(forAccountKeychainId:from:accountService:dependencies:)` are referenced with matching signatures across tasks.

**Known verification points for the implementer/reviewer:**
- `reader`/`writer` accessor names on `AppDatabase` (Task 1 Step 8) -- match the codebase's existing observation/read helpers.
- `accountIdentifierForLogging` is the plain keychain id in `LemmyService` (Task 2 Step 3) -- confirmed by its use as `upsertAccount(keychainId:)`.
- `dependencies.nested` conforms to `LoginViewController.Dependencies` at each launcher call site (MainWindow / AccountViewController / AccountListViewController) -- each already builds login-flow VCs from that set.
- Every other `OutboxFailure(...)` construction updated for the new field (Task 2 Step 7).
- Every `AccountServiceType` test double implements the two new protocol methods (Task 3 Step 4).
