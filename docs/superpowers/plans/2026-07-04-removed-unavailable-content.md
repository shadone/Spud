# Removed / unavailable content handling — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Detect when a post no longer exists server-side (`couldnt_find_post`), mark it locally, and surface it honestly — a "no longer available" placeholder on the detail screen, a neutral badge in the feed, and a specific interaction toast — instead of showing stale content that silently fails.

**Architecture:** A new persisted `PostRecord.isUnavailable` flag (migration `v28`), distinct from `isRemoved`/`isDeleted`. One shared `ContentNotFound` classifier recognizes the not-found error. Read paths (`getPost`, `getComments`) and the outbox rollback both funnel into one idempotent `markPostUnavailable` DB write; the feed cell and detail screen react via the existing GRDB observations. A shared `PostUnavailableViewController` replaces the detail content, gated so moderators and authors keep visibility.

**Tech Stack:** Swift 6, UIKit, GRDB, LemmyKit (remote SPM pin), Swift Testing, swift-snapshot-testing.

## Global Constraints

- Swift 6 language mode + `SWIFT_STRICT_CONCURRENCY = complete` on every shipped + unit-test target. New SpudDataKit / Spud / test code must compile clean under it.
- Unit tests are **Swift Testing** (`import Testing`, `struct` suites, `@Test`, `#expect`/`#require`). `import Testing` does NOT re-export Foundation — add `import Foundation` when using `Date`/`URL`/`Data`/`URLError`.
- Swift Testing runs a suite's tests in **parallel**; suites touching process-global state need `@Suite(.serialized)`. Per-test `AppDatabase.inMemory()` is already isolated.
- No emojis in code, comments, docs, or commit messages. Conventional commit subjects (`feat:`/`fix:`/`refactor:`/`test:`/`docs:`).
- Migrations are append-only: add the next `registerMigration` case; never edit an existing one. Current latest is `v27_voteEvent`; the new one is **`v28_postUnavailable`**.
- Run `mint run swiftformat <changed paths>` **before** the final test verify of each task, never after a green verify (a formatting rewrite can break the build — e.g. `--enable isEmpty`).
- Default branch is `main`. Verify `git branch --show-current` before each commit (shared checkout; never commit under `.claude/worktrees/`, never stage `.remember/remember.md`). Stage explicit paths, never `git add -A` (`git status` here hides untracked files — use `git status -uall`).
- Snapshot references record on **iPhone 17 Pro, iOS 26.3.1**, portrait. `.image(size:traits:)` and app-level snapshots are runtime-sensitive.
- Wording (copy verbatim): unavailable → `"This post is no longer available"` (subtitle `"It may have been removed."`); removed → `"Removed by moderator"`; deleted → `"Deleted by author"`; interaction toast (not-found) → `"This post is no longer available"`.
- Feed "unavailable" badge is **neutral** (`exclamationmark.octagon`, `.secondaryLabel`), NOT red. Red `trash.slash.fill` / `trash.fill` stay for the server-confirmed removed/deleted cases.

---

### Task 1: Persist the `isUnavailable` flag (data layer)

Adds the column, migration, importer-clear, the targeted write, and the async wrappers. This is the persistence foundation every later task builds on.

**Files:**
- Modify: `SpudDataKit/Services/AppDatabase/Records/Post.swift`
- Modify: `SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift` (append after `v27_voteEvent`, ~`:760`)
- Modify: `SpudDataKit/Services/AppDatabase/Importers/PostImporter.swift:207`
- Modify: `SpudDataKit/Services/AppDatabase/OptimisticWrites.swift`
- Create: `SpudDataKit/Services/AppDatabase/PostUnavailableWrites.swift`
- Modify: `SpudDataKitTests/Outbox/OutboxTestSupport.swift` (add a `readPostUnavailable` helper)
- Test: `SpudDataKitTests/AppDatabase/MarkPostUnavailableTests.swift`

**Interfaces:**
- Produces:
  - `PostRecord.isUnavailable: Bool` (persisted column, default `false`).
  - `OptimisticWrites.setPostUnavailable(_ db: Database, accountId: Int64, serverPostId: Int64, isUnavailable: Bool) throws`
  - `AppDatabase.markPostUnavailable(accountId: Int64, serverPostId: Int64) async throws` — sets `isUnavailable = true`.
  - `AppDatabase.markPostUnavailable(forKeychainId keychainId: String, serverPostId: Int64) async throws` — resolves the account row id, then sets the flag.
  - Test helper `readPostUnavailable(_ appDatabase:accountId:serverPostId:) async throws -> Bool`.

- [ ] **Step 1: Write the failing test**

Create `SpudDataKitTests/AppDatabase/MarkPostUnavailableTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import LemmyKit
import Testing
@testable import SpudDataKit

@MainActor
struct MarkPostUnavailableTests {
    @Test
    func markSetsFlagByAccountId() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId) = try await seedAccountAndSite(appDatabase)
        let postId = try await seedPost(appDatabase, accountId: accountId, siteId: siteId, score: 0, voteStatus: nil)

        #expect(try await readPostUnavailable(appDatabase, accountId: accountId, serverPostId: postId) == false)

        try await appDatabase.markPostUnavailable(accountId: accountId, serverPostId: postId)

        #expect(try await readPostUnavailable(appDatabase, accountId: accountId, serverPostId: postId) == true)
    }

    @Test
    func markSetsFlagByKeychainId() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId) = try await seedAccountAndSite(appDatabase)
        let postId = try await seedPost(appDatabase, accountId: accountId, siteId: siteId, score: 0, voteStatus: nil)

        try await appDatabase.markPostUnavailable(forKeychainId: "keychain-outbox-test", serverPostId: postId)

        #expect(try await readPostUnavailable(appDatabase, accountId: accountId, serverPostId: postId) == true)
    }

    @Test
    func freshPostViewImportClearsFlag() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId) = try await seedAccountAndSite(appDatabase)
        let postId = try await seedPost(appDatabase, accountId: accountId, siteId: siteId, score: 0, voteStatus: nil)
        try await appDatabase.markPostUnavailable(accountId: accountId, serverPostId: postId)
        #expect(try await readPostUnavailable(appDatabase, accountId: accountId, serverPostId: postId) == true)

        // A fresh authoritative PostView means the post is available again.
        let view = makePostView(postId: postId, myVote: nil, score: 0)
        try await appDatabase.upsertPost(from: view, accountId: accountId, siteId: siteId)

        #expect(try await readPostUnavailable(appDatabase, accountId: accountId, serverPostId: postId) == false)
    }
}
```

Add this helper to the end of `SpudDataKitTests/Outbox/OutboxTestSupport.swift` (in the "Read helpers" section):

```swift
func readPostUnavailable(
    _ appDatabase: AppDatabase,
    accountId: Int64,
    serverPostId: Int64
) async throws -> Bool {
    try await appDatabase.writer.read { db -> Bool in
        let row = try PostRecord
            .filter(Column("postId") == serverPostId)
            .filter(Column("accountId") == accountId)
            .fetchOne(db)
        return row?.isUnavailable ?? false
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudDataKitTests/MarkPostUnavailableTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: FAIL to compile — `PostRecord` has no member `isUnavailable`, `markPostUnavailable` undefined.

- [ ] **Step 3a: Add the column to `PostRecord`**

In `Post.swift`, after `public var isDeleted: Bool` (`:52`) add:
```swift
    /// The server rejected a request for this post with `couldnt_find_post`
    /// (removed on its origin, author-deleted, or de-federated) while we still
    /// hold a stale cached copy. Distinct from `isRemoved`/`isDeleted`, which
    /// mean the server returned the post object and told us so; `isUnavailable`
    /// means we only know it is gone, not why. Cleared by a fresh PostView import.
    public var isUnavailable: Bool
```
Add the init parameter (after `isDeleted: Bool = false,` at `:86`):
```swift
        isDeleted: Bool = false,
        isUnavailable: Bool = false,
```
Add the assignment (after `self.isDeleted = isDeleted` at `:119`):
```swift
        self.isUnavailable = isUnavailable
```

- [ ] **Step 3b: Add migration `v28_postUnavailable`**

In `AppDatabase+Migrations.swift`, after the `v27_voteEvent` block closes, add:
```swift
        migrator.registerMigration("v28_postUnavailable") { db in
            // Set when the server rejects a request for a post with
            // `couldnt_find_post` while we still hold a stale cached copy.
            // Distinct from isRemoved/isDeleted (which the server affirms via a
            // returned post object); this only records "gone, reason unknown".
            // Cleared by any fresh PostView import.
            try db.alter(table: "post") { t in
                t.add(column: "isUnavailable", .boolean).notNull().defaults(to: false)
            }
        }
```

- [ ] **Step 3c: Clear the flag on import**

In `PostImporter.swift`, in `apply(view:to:now:)` after `record.isDeleted = post.deleted` (`:207`) add:
```swift
        // A fresh authoritative PostView means the post exists again — clear any
        // stale "unavailable" tombstone from a prior couldnt_find_post.
        record.isUnavailable = false
```

- [ ] **Step 3d: Add the targeted write**

In `OptimisticWrites.swift`, after `setPostDeleted` (`:67`) add:
```swift
    public static func setPostUnavailable(
        _ db: Database,
        accountId: Int64,
        serverPostId: Int64,
        isUnavailable: Bool
    ) throws {
        try db.execute(
            sql: "UPDATE post SET isUnavailable = ? WHERE postId = ? AND accountId = ?",
            arguments: [isUnavailable, serverPostId, accountId]
        )
    }
```

- [ ] **Step 3e: Add the async wrappers**

Create `SpudDataKit/Services/AppDatabase/PostUnavailableWrites.swift`:
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

public extension AppDatabase {
    /// Marks a post as no longer available on the server (`couldnt_find_post`).
    /// Idempotent; a no-op if no matching row exists. Cleared by a later PostView
    /// import (see `PostImporter`).
    func markPostUnavailable(accountId: Int64, serverPostId: Int64) async throws {
        try await writer.write { db in
            try OptimisticWrites.setPostUnavailable(
                db,
                accountId: accountId,
                serverPostId: serverPostId,
                isUnavailable: true
            )
        }
    }

    /// Keychain-scoped variant for callers (e.g. `LemmyService`) that hold the
    /// account's keychain id rather than its row id. Resolves the account row id
    /// inside the same write; a no-op if the account or post row is absent.
    func markPostUnavailable(forKeychainId keychainId: String, serverPostId: Int64) async throws {
        try await writer.write { db in
            guard let accountId = try PostInteractionWrites.accountRowId(forKeychainId: keychainId, in: db) else {
                return
            }
            try OptimisticWrites.setPostUnavailable(
                db,
                accountId: accountId,
                serverPostId: serverPostId,
                isUnavailable: true
            )
        }
    }
}
```
(Reuses the existing `internal static PostInteractionWrites.accountRowId(forKeychainId:in:)` at `PostInteractionWrites.swift:92`.)

- [ ] **Step 4: Run tests to verify they pass**

Run the Step 2 command. Expected: `✔ Test run with 3 tests ... passed` (MarkPostUnavailableTests). Then run the existing `OptimisticWritesTests` and `LemmyServiceFetchPersistenceTests` to confirm the importer change didn't regress:
```bash
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudDataKitTests/OptimisticWritesTests \
  -only-testing:SpudDataKitTests/LemmyServiceFetchPersistenceTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: PASS.

- [ ] **Step 5: Format and commit**

```bash
mint run swiftformat SpudDataKit/Services/AppDatabase/Records/Post.swift SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift SpudDataKit/Services/AppDatabase/Importers/PostImporter.swift SpudDataKit/Services/AppDatabase/OptimisticWrites.swift SpudDataKit/Services/AppDatabase/PostUnavailableWrites.swift SpudDataKitTests/AppDatabase/MarkPostUnavailableTests.swift SpudDataKitTests/Outbox/OutboxTestSupport.swift
make project   # PostUnavailableWrites.swift + MarkPostUnavailableTests.swift are new files
git add SpudDataKit/Services/AppDatabase/Records/Post.swift SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift SpudDataKit/Services/AppDatabase/Importers/PostImporter.swift SpudDataKit/Services/AppDatabase/OptimisticWrites.swift SpudDataKit/Services/AppDatabase/PostUnavailableWrites.swift SpudDataKitTests/AppDatabase/MarkPostUnavailableTests.swift SpudDataKitTests/Outbox/OutboxTestSupport.swift
git commit -m "feat: persist post isUnavailable flag (migration v28)"
```

---

### Task 2: `ContentNotFound` classifier

Single source of truth for recognizing the post-not-found error. Pure and standalone.

**Files:**
- Create: `SpudDataKit/Services/Lemmy/ContentNotFound.swift`
- Test: `SpudDataKitTests/ContentNotFoundTests.swift`

**Interfaces:**
- Produces: `enum ContentNotFound { static func matchesPost(_ error: Error) -> Bool }`. Returns `true` for `LemmyApiError.serverError(r)` and `LemmyServiceError.apiError(.serverError(r))` where `r.error == "couldnt_find_post"`; `false` otherwise.

- [ ] **Step 1: Write the failing test**

Create `SpudDataKitTests/ContentNotFoundTests.swift`:
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

struct ContentNotFoundTests {
    private func serverError(_ code: String) -> LemmyApiError {
        .serverError(Components.Schemas.ErrorResponse(error: code, message: nil))
    }

    @Test
    func couldntFindPostMatches() {
        #expect(ContentNotFound.matchesPost(serverError("couldnt_find_post")))
    }

    @Test
    func wrappedCouldntFindPostMatches() {
        #expect(ContentNotFound.matchesPost(LemmyServiceError.apiError(serverError("couldnt_find_post"))))
    }

    @Test
    func couldntLikePostDoesNotMatch() {
        #expect(!ContentNotFound.matchesPost(serverError("couldnt_like_post")))
    }

    @Test
    func rateLimitDoesNotMatch() {
        #expect(!ContentNotFound.matchesPost(serverError("rate_limit_error")))
    }

    @Test
    func networkErrorDoesNotMatch() {
        #expect(!ContentNotFound.matchesPost(URLError(.timedOut)))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudDataKitTests/ContentNotFoundTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: FAIL to compile — `ContentNotFound` undefined.

- [ ] **Step 3: Implement**

Create `SpudDataKit/Services/Lemmy/ContentNotFound.swift`:
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

/// Recognizes the Lemmy "this post does not exist" rejection so read paths and
/// the outbox can mark a stale cached post as unavailable. The only place the
/// `couldnt_find_post` error code is matched — mirrors `OutboxFailureClass` /
/// `LoadFailure` in style.
public enum ContentNotFound {
    /// The Lemmy error codes that mean "the requested post is gone". Lemmy does
    /// not distinguish mod-removed / author-deleted / de-federated here.
    private static let postCodes: Set<String> = ["couldnt_find_post"]

    /// `true` when `error` is a structured Lemmy rejection whose code means the
    /// post no longer exists, unwrapping both the bare `LemmyApiError` and the
    /// `LemmyServiceError.apiError` wrapper.
    public static func matchesPost(_ error: Error) -> Bool {
        switch error {
        case let apiError as LemmyApiError:
            return matchesPost(apiError)
        case let .apiError(apiError) as LemmyServiceError:
            return matchesPost(apiError)
        default:
            return false
        }
    }

    private static func matchesPost(_ apiError: LemmyApiError) -> Bool {
        guard case let .serverError(errorResponse) = apiError else { return false }
        return postCodes.contains(errorResponse.error)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run the Step 2 command. Expected: `✔ Test run with 5 tests ... passed`.

- [ ] **Step 5: Format and commit**

```bash
mint run swiftformat SpudDataKit/Services/Lemmy/ContentNotFound.swift SpudDataKitTests/ContentNotFoundTests.swift
make project   # both files are new
git add SpudDataKit/Services/Lemmy/ContentNotFound.swift SpudDataKitTests/ContentNotFoundTests.swift
git commit -m "feat: add ContentNotFound classifier for couldnt_find_post"
```

---

### Task 3: Outbox marks the post + carries `.notFound` + specific toast

When a vote/save/hide on a post permanently fails with `couldnt_find_post`, mark the post unavailable and tag the failure so `MainWindow` shows a specific toast. This is the exact path the user hit.

**Files:**
- Modify: `SpudDataKit/Services/Outbox/OutboxService.swift` (`OutboxFailure` struct `:10`; permanent branch `:219-257`)
- Modify: `Spud/Scenes/MainWindow/MainWindow.swift:361` (`presentOutboxFailureToast`)
- Test: `SpudDataKitTests/Outbox/OutboxServiceTests.swift` (add a test)

**Interfaces:**
- Consumes: `ContentNotFound.matchesPost` (Task 2); `AppDatabase.markPostUnavailable(accountId:serverPostId:)` (Task 1).
- Produces:
  - `enum OutboxFailureReason: Sendable, Equatable { case notFound; case other }`
  - `OutboxFailure` gains `public let reason: OutboxFailureReason` (added to init).

- [ ] **Step 1: Write the failing test**

Add to `OutboxServiceTests.swift` (model on `permanentFailureRollsBackAndEmits`):
```swift
    @Test
    func notFoundVoteMarksPostUnavailableAndReportsReason() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId) = try await seedAccountAndSite(appDatabase)
        let postId = try await seedPost(appDatabase, accountId: accountId, siteId: siteId, score: 5, voteStatus: nil)
        let performer = FakeOutboxPerformer()
        let notFound = LemmyApiError.serverError(
            Components.Schemas.ErrorResponse(error: "couldnt_find_post", message: nil)
        )
        await performer.setOutcome(.fail(notFound), for: .vote)
        let service = makeService(appDatabase, performer, accountId: accountId)

        var events: [OutboxFailure] = []
        let stream = await service.failureEvents
        let collector = Task { for await event in stream {
            events.append(event)
            break
        } }

        await service.enqueue(.init(entityType: .post, entityServerId: postId, desiredState: .vote(.liked)))
        _ = await collector.value

        #expect(try await readPostUnavailable(appDatabase, accountId: accountId, serverPostId: postId) == true)
        #expect(events.count == 1)
        #expect(events[0].reason == .notFound)
        #expect(events[0].kind == .vote)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudDataKitTests/OutboxServiceTests/notFoundVoteMarksPostUnavailableAndReportsReason \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: FAIL to compile — `OutboxFailure` has no member `reason`.

- [ ] **Step 3a: Extend `OutboxFailure`**

In `OutboxService.swift`, replace the struct (`:10-14`):
```swift
/// Why an outbox operation permanently failed, when the UI needs to react
/// differently. `.notFound` means the target post no longer exists on the
/// server (`couldnt_find_post`); everything else is `.other`.
public enum OutboxFailureReason: Sendable, Equatable {
    case notFound
    case other
}

public struct OutboxFailure: Sendable, Equatable {
    public let entityType: OutboxEntityType
    public let entityServerId: Int64
    public let kind: OutboxKind
    public let reason: OutboxFailureReason
}
```

- [ ] **Step 3b: Mark + tag in the permanent branch**

In the `.permanent` branch, after the vote-event cleanup block (`:250`, right before `rolledBack += 1`) add:
```swift
                    // A not-found rejection means the post is gone server-side.
                    // Tombstone the stale cache so the feed badge + detail
                    // placeholder reflect reality, and tag the failure so the
                    // toast can be specific.
                    let reason: OutboxFailureReason
                    if op.entityType == .post, ContentNotFound.matchesPost(error) {
                        try? await appDatabase.markPostUnavailable(
                            accountId: accountId,
                            serverPostId: op.entityServerId
                        )
                        reason = .notFound
                    } else {
                        reason = .other
                    }
```
Then change the `emitFailure(...)` call (`:252-256`) to pass `reason: reason`:
```swift
                    emitFailure(OutboxFailure(
                        entityType: op.entityType,
                        entityServerId: op.entityServerId,
                        kind: op.kind,
                        reason: reason
                    ))
```

- [ ] **Step 3c: Fix other `OutboxFailure(...)` construction sites**

Search and update any remaining constructor callers (Equatable/init now requires `reason`):
```bash
grep -rn "OutboxFailure(" SpudDataKit SpudDataKitTests Spud
```
`permanentFailureRollsBackAndEmits` asserts on the emitted event, not its construction, so it needs no change. Any test that *constructs* an `OutboxFailure` literal must add `reason: .other`.

- [ ] **Step 3d: Specific toast in `MainWindow`**

In `MainWindow.swift`, replace `presentOutboxFailureToast` (`:361`) body:
```swift
    private func presentOutboxFailureToast(_ failure: OutboxFailure) {
        let message: String
        if failure.reason == .notFound {
            message = NSLocalizedString(
                "This post is no longer available",
                comment: "Toast when an action failed because the post was removed/deleted on the server"
            )
        } else {
            switch failure.kind {
            case .vote:
                message = NSLocalizedString("Couldn't vote", comment: "Toast when a vote permanently failed and was reverted")
            case .save:
                message = NSLocalizedString("Couldn't save", comment: "Toast when a save permanently failed and was reverted")
            case .hide:
                message = NSLocalizedString("Couldn't hide", comment: "Toast when a hide permanently failed and was reverted")
            case .delete:
                message = NSLocalizedString("Couldn't update comment", comment: "Toast when a comment delete/restore permanently failed and was reverted")
            }
        }
        ToastPresenter.shared.show(message, in: self)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run the new test plus the existing outbox suites (to catch any missed constructor site):
```bash
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudDataKitTests/OutboxServiceTests \
  -only-testing:SpudDataKitTests/OutboxServiceDiagnosticsTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: PASS. Then build the app target so the `MainWindow` change compiles:
```bash
python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud
```
Expected: build succeeds.

- [ ] **Step 5: Format and commit**

```bash
mint run swiftformat SpudDataKit/Services/Outbox/OutboxService.swift Spud/Scenes/MainWindow/MainWindow.swift SpudDataKitTests/Outbox/OutboxServiceTests.swift
git add SpudDataKit/Services/Outbox/OutboxService.swift Spud/Scenes/MainWindow/MainWindow.swift SpudDataKitTests/Outbox/OutboxServiceTests.swift
git commit -m "feat: mark post unavailable on not-found outbox failure with specific toast"
```

---

### Task 4: Read paths mark the post on not-found (`getPost` / `getComments`)

So opening a post whose comment fetch 404s, or pull-to-refresh, marks it unavailable too — not just interactions.

**Files:**
- Modify: `SpudDataKit/Services/Lemmy/LemmyService.swift` (`fetchPostInfo` catch `~:2090`; `fetchComments` catch `~:855`)
- Test: `SpudDataKitTests/LemmyServiceContentNotFoundTests.swift`

**Interfaces:**
- Consumes: `ContentNotFound.matchesPost` (Task 2); `AppDatabase.markPostUnavailable(forKeychainId:serverPostId:)` (Task 1).

- [ ] **Step 1: Write the failing test**

Create `SpudDataKitTests/LemmyServiceContentNotFoundTests.swift`. Model the LemmyService + stub-transport construction on `LemmyServiceFetchPersistenceTests.swift` (same file's `StubGetPostTransport` pattern), but return a not-found error body. Write it to first prove the thrown error is what `ContentNotFound` matches, then assert the flag:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import HTTPTypes
import LemmyKit
import OpenAPIRuntime
import Testing
@testable import SpudDataKit

@MainActor
struct LemmyServiceContentNotFoundTests {
    /// Transport that fails `getPost` with Lemmy's not-found error body. The
    /// exact HTTP status LemmyKit maps to `.serverError(ErrorResponse)` is what
    /// the real API returns for a removed post; if this stub yields a different
    /// LemmyApiError case, adjust `status` until `ContentNotFound.matchesPost`
    /// is satisfied (the first #expect below guards that).
    private final class NotFoundGetPostTransport: ClientTransport, @unchecked Sendable {
        func send(
            _: HTTPRequest, body _: HTTPBody?, baseURL _: URL, operationID: String
        ) async throws -> (HTTPResponse, HTTPBody?) {
            let body = Data(#"{"error":"couldnt_find_post"}"#.utf8)
            var response = HTTPResponse(status: .badRequest)
            response.headerFields[.contentType] = "application/json"
            return (response, HTTPBody(body))
        }
    }

    @Test
    func getPostNotFoundMarksPostUnavailable() async throws {
        // Reuse the harness from LemmyServiceFetchPersistenceTests to build an
        // AppDatabase-backed LemmyService with a seeded account + cached post,
        // then swap in NotFoundGetPostTransport. See that file for the exact
        // makeService(...) helper to copy.
        let harness = try await LemmyServiceContentNotFoundHarness.make(transport: NotFoundGetPostTransport())

        var thrown: Error?
        do {
            try await harness.service.fetchPostInfo(serverPostId: harness.serverPostId)
        } catch {
            thrown = error
        }

        // Guard: the wiring only fires if the error is actually a not-found.
        #expect(thrown.map(ContentNotFound.matchesPost) == true)
        #expect(try await readPostUnavailable(harness.appDatabase, accountId: harness.accountId, serverPostId: Int64(harness.serverPostId)) == true)
    }
}
```

Implement `LemmyServiceContentNotFoundHarness` in the same file: a small factory that seeds an account + one cached post (via `seedAccountAndSite` / `seedPost` from `OutboxTestSupport`) and constructs a `LemmyService` with the given transport. Copy the `LemmyService(...)` construction verbatim from `LemmyServiceFetchPersistenceTests.swift`'s service-builder; expose `service`, `appDatabase`, `accountId`, `serverPostId`.

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudDataKitTests/LemmyServiceContentNotFoundTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: FAIL — flag not set (read paths don't mark yet). If the first `#expect` (the guard) fails instead, adjust `NotFoundGetPostTransport.status` until LemmyKit surfaces `.serverError` (per the user's real log it does).

- [ ] **Step 3: Implement — mark in both catch blocks**

In `fetchPostInfo`'s `catch` (before `throw LemmyServiceError(from: error)`, `~:2091`):
```swift
        } catch {
            logger.error("""
                Fetch post failed. postId=\(serverPostId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            if ContentNotFound.matchesPost(error) {
                try? await appDatabase.markPostUnavailable(
                    forKeychainId: accountIdentifierForLogging,
                    serverPostId: Int64(serverPostId)
                )
            }
            throw LemmyServiceError(from: error)
        }
```
Apply the identical `if ContentNotFound.matchesPost(error) { ... }` block in `fetchComments`'s `catch` (before its `throw LemmyServiceError(from: error)`, `~:857`).

- [ ] **Step 4: Run test to verify it passes**

Run the Step 2 command. Expected: PASS (both `#expect`).

- [ ] **Step 5: Format and commit**

```bash
mint run swiftformat SpudDataKit/Services/Lemmy/LemmyService.swift SpudDataKitTests/LemmyServiceContentNotFoundTests.swift
make project   # new test file
git add SpudDataKit/Services/Lemmy/LemmyService.swift SpudDataKitTests/LemmyServiceContentNotFoundTests.swift
git commit -m "feat: mark post unavailable when getPost/getComments returns couldnt_find_post"
```

---

### Task 5: Carry `isUnavailable` into the rows + neutral feed badge

Row structs and the feed cell react to the flag.

**Files:**
- Modify: `SpudDataKit/Services/AppDatabase/PostListObservations.swift` (`PostListRow` struct + init + SELECT `:167,:171,:223,:227`)
- Modify: `SpudDataKit/Services/AppDatabase/PostDetailObservations.swift` (`PostDetailHeaderRow` struct + init + SELECT `:296,:345`)
- Modify: `Spud/Scenes/Shared/PostStatusBadge.swift`
- Test: `SpudTests/PostStatusBadgeTests.swift`

**Interfaces:**
- Produces: `PostListRow.isUnavailable: Bool`, `PostDetailHeaderRow.isUnavailable: Bool`; `PostStatusBadge.badges(for:)` renders a neutral `exclamationmark.octagon` / `.secondaryLabel` badge when `isUnavailable && !isRemoved && !isDeleted`.

- [ ] **Step 1: Write the failing test**

Create `SpudTests/PostStatusBadgeTests.swift`:
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
import UIKit
@testable import Spud

struct PostStatusBadgeTests {
    @Test
    func unavailableShowsNeutralBadge() {
        let badges = PostStatusBadge.badges(
            isRemoved: false, isDeleted: false, isUnavailable: true,
            isLocked: false, isFeatured: false
        )
        #expect(badges.count == 1)
        #expect(badges[0].symbolName == "exclamationmark.octagon")
        #expect(badges[0].color == .secondaryLabel)
    }

    @Test
    func removedTakesPriorityOverUnavailable() {
        let badges = PostStatusBadge.badges(
            isRemoved: true, isDeleted: false, isUnavailable: true,
            isLocked: false, isFeatured: false
        )
        #expect(badges.count == 1)
        #expect(badges[0].symbolName == "trash.slash.fill")
        #expect(badges[0].color == .systemRed)
    }

    @Test
    func availablePostHasNoStatusBadge() {
        let badges = PostStatusBadge.badges(
            isRemoved: false, isDeleted: false, isUnavailable: false,
            isLocked: false, isFeatured: false
        )
        #expect(badges.isEmpty)
    }
}
```
This calls the private helper directly — so make it accessible: change `private static func badges(isRemoved:...)` to `static func badges(isRemoved:...)` (internal) in Step 3.

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudTests/PostStatusBadgeTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: FAIL to compile — `badges(isRemoved:...)` has no `isUnavailable` param and is private.

- [ ] **Step 3a: Add `isUnavailable` to the rows**

`PostListObservations.swift`: after `public let isDeleted: Bool` (`:61`) add `public let isUnavailable: Bool`; add `isUnavailable: Bool = false,` to the init parameter list next to `isDeleted` (**defaulted** so existing row fixtures don't need updating — only the observation builder and the Task 8 fixture set it); add `self.isUnavailable = isUnavailable` to the init body. In the SELECT after `post.isDeleted AS isDeleted,` (`:171`) add `post.isUnavailable AS isUnavailable,`; in the row builder after `isDeleted: row["isDeleted"],` (`:227`) add `isUnavailable: row["isUnavailable"],`.

`PostDetailObservations.swift`: identically add `public let isUnavailable: Bool` to `PostDetailHeaderRow` (after `isDeleted` `:66`), the init param `isUnavailable: Bool = false,` (**defaulted**) + body assignment; SELECT `post.isUnavailable AS isUnavailable,` after `post.isDeleted ... AS isDeleted,` (`:296`); builder `isUnavailable: row["isUnavailable"],` after `isDeleted: row["isDeleted"],` (`:345`).

- [ ] **Step 3b: Render the neutral badge**

Replace `PostStatusBadge.swift`'s three `badges` functions:
```swift
    static func badges(for row: PostListRow) -> [PostStatusBadge] {
        badges(
            isRemoved: row.isRemoved,
            isDeleted: row.isDeleted,
            isUnavailable: row.isUnavailable,
            isLocked: row.isLocked,
            isFeatured: row.isFeaturedCommunity || row.isFeaturedLocal
        )
    }

    static func badges(for row: PostDetailHeaderRow) -> [PostStatusBadge] {
        badges(
            isRemoved: row.isRemoved,
            isDeleted: row.isDeleted,
            isUnavailable: row.isUnavailable,
            isLocked: row.isLocked,
            isFeatured: row.isFeaturedCommunity || row.isFeaturedLocal
        )
    }

    static func badges(
        isRemoved: Bool,
        isDeleted: Bool,
        isUnavailable: Bool,
        isLocked: Bool,
        isFeatured: Bool
    ) -> [PostStatusBadge] {
        var badges: [PostStatusBadge] = []
        if isRemoved {
            badges.append(.init(symbolName: "trash.slash.fill", color: .systemRed))
        } else if isDeleted {
            badges.append(.init(symbolName: "trash.fill", color: .systemRed))
        } else if isUnavailable {
            // Neutral, not red: for `couldnt_find_post` we know the post is gone
            // but not whether it was removed, deleted, or de-federated.
            badges.append(.init(symbolName: "exclamationmark.octagon", color: .secondaryLabel))
        }
        if isFeatured {
            badges.append(.init(symbolName: "pin.fill", color: .systemGreen))
        }
        if isLocked {
            badges.append(.init(symbolName: "lock.fill", color: .systemYellow))
        }
        return badges
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run the Step 2 command. Expected: `✔ Test run with 3 tests ... passed`. Then build the app + widget to confirm the row-struct change compiles for all callers:
```bash
python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud
```
Expected: build succeeds. The defaulted init param means existing `PostListRow`/`PostDetailHeaderRow` fixtures compile unchanged.

- [ ] **Step 5: Format and commit**

```bash
mint run swiftformat SpudDataKit/Services/AppDatabase/PostListObservations.swift SpudDataKit/Services/AppDatabase/PostDetailObservations.swift Spud/Scenes/Shared/PostStatusBadge.swift SpudTests/PostStatusBadgeTests.swift
make project   # new test file
git add SpudDataKit/Services/AppDatabase/PostListObservations.swift SpudDataKit/Services/AppDatabase/PostDetailObservations.swift Spud/Scenes/Shared/PostStatusBadge.swift SpudTests/PostStatusBadgeTests.swift
git commit -m "feat: neutral unavailable badge in feed + header rows carry isUnavailable"
```

---

### Task 6: `PostUnavailableViewController` + gating reason

The placeholder screen and the pure gating function that decides when to show it.

**Files:**
- Create: `Spud/Scenes/PostDetail/Unavailable/PostUnavailableViewController.swift`
- Create: `Spud/Scenes/PostDetail/Unavailable/PostUnavailableReason.swift`
- Test: `SpudTests/PostUnavailableReasonTests.swift`

**Interfaces:**
- Produces:
  - `enum PostUnavailableReason: Equatable { case unavailable, removed, deleted }` with `var title: String` / `var subtitle: String?` / `var symbolName: String`.
  - `static func PostUnavailableReason.forHeader(isRemoved:isDeleted:isUnavailable:canModerate:isOwnPost:) -> PostUnavailableReason?` — the gating rule.
  - `final class PostUnavailableViewController: UIViewController` with `init(reason: PostUnavailableReason)`.

- [ ] **Step 1: Write the failing test**

Create `SpudTests/PostUnavailableReasonTests.swift`:
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
@testable import Spud

struct PostUnavailableReasonTests {
    private func reason(
        removed: Bool = false, deleted: Bool = false, unavailable: Bool = false,
        canModerate: Bool = false, isOwnPost: Bool = false
    ) -> PostUnavailableReason? {
        PostUnavailableReason.forHeader(
            isRemoved: removed, isDeleted: deleted, isUnavailable: unavailable,
            canModerate: canModerate, isOwnPost: isOwnPost
        )
    }

    @Test func availablePostShowsNothing() { #expect(reason() == nil) }

    @Test func unavailableShowsUnavailable() {
        #expect(reason(unavailable: true) == .unavailable)
    }

    @Test func removedNonModShowsRemoved() {
        #expect(reason(removed: true) == .removed)
    }

    @Test func removedModKeepsContent() {
        #expect(reason(removed: true, canModerate: true) == nil)
    }

    @Test func ownDeletedKeepsContent() {
        #expect(reason(deleted: true, isOwnPost: true) == nil)
    }

    @Test func otherDeletedShowsDeleted() {
        #expect(reason(deleted: true) == .deleted)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudTests/PostUnavailableReasonTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: FAIL to compile — `PostUnavailableReason` undefined.

- [ ] **Step 3a: Implement the reason enum + gating**

Create `Spud/Scenes/PostDetail/Unavailable/PostUnavailableReason.swift`:
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Why the post-detail screen shows the "content unavailable" placeholder
/// instead of the post. Drives the placeholder copy + glyph.
enum PostUnavailableReason: Equatable {
    /// The server rejected the request (`couldnt_find_post`); we do not know why.
    case unavailable
    /// The server returned the post marked removed by a moderator.
    case removed
    /// The server returned the post marked deleted by its author.
    case deleted

    var title: String {
        switch self {
        case .unavailable:
            return NSLocalizedString("This post is no longer available", comment: "Placeholder title: post 404s on the server")
        case .removed:
            return NSLocalizedString("Removed by moderator", comment: "Placeholder title: post removed by a moderator")
        case .deleted:
            return NSLocalizedString("Deleted by author", comment: "Placeholder title: post deleted by its author")
        }
    }

    var subtitle: String? {
        switch self {
        case .unavailable:
            return NSLocalizedString("It may have been removed.", comment: "Placeholder subtitle for an unavailable post")
        case .removed, .deleted:
            return nil
        }
    }

    var symbolName: String {
        switch self {
        case .unavailable: return "exclamationmark.octagon"
        case .removed: return "trash.slash"
        case .deleted: return "trash"
        }
    }

    /// The placeholder to show for a post-detail header, or `nil` to keep
    /// showing the content. Moderators keep seeing removed posts (they can
    /// Restore); authors keep seeing their own deleted posts (they can Restore).
    static func forHeader(
        isRemoved: Bool,
        isDeleted: Bool,
        isUnavailable: Bool,
        canModerate: Bool,
        isOwnPost: Bool
    ) -> PostUnavailableReason? {
        if isUnavailable { return .unavailable }
        if isRemoved { return canModerate ? nil : .removed }
        if isDeleted { return (isOwnPost || canModerate) ? nil : .deleted }
        return nil
    }
}
```

- [ ] **Step 3b: Implement the view controller**

Create `Spud/Scenes/PostDetail/Unavailable/PostUnavailableViewController.swift` (modeled on `PostDetailLoadingViewController`'s centered stack + `PostDetailEmptyViewController` styling):
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudUIKit
import UIKit

/// Centered placeholder shown in the post-detail column when the post no longer
/// exists on the server (removed / deleted / de-federated). Replaces the stale
/// cached content. See `PostUnavailableReason` for copy + gating.
final class PostUnavailableViewController: UIViewController {
    private let reason: PostUnavailableReason

    init(reason: PostUnavailableReason) {
        self.reason = reason
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background

        let imageView = UIImageView(image: UIImage(systemName: reason.symbolName))
        imageView.tintColor = .tertiaryLabel
        imageView.contentMode = .scaleAspectFit
        imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 44, weight: .light)
        imageView.isAccessibilityElement = false

        let titleLabel = UILabel()
        titleLabel.text = reason.title
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .secondaryLabel
        titleLabel.adjustsFontForContentSizeCategory = true

        let stack = UIStackView(arrangedSubviews: [imageView, titleLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        if let subtitle = reason.subtitle {
            let subtitleLabel = UILabel()
            subtitleLabel.text = subtitle
            subtitleLabel.textAlignment = .center
            subtitleLabel.numberOfLines = 0
            subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
            subtitleLabel.textColor = .tertiaryLabel
            subtitleLabel.adjustsFontForContentSizeCategory = true
            stack.addArrangedSubview(subtitleLabel)
        }

        // One VoiceOver element reading the full message.
        stack.isAccessibilityElement = true
        stack.accessibilityTraits = .staticText
        stack.accessibilityLabel = [reason.title, reason.subtitle].compactMap { $0 }.joined(separator: ". ")

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run the Step 2 command. Expected: `✔ Test run with 6 tests ... passed`. Confirm the VC compiles:
```bash
python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud
```
Expected: build succeeds.

- [ ] **Step 5: Format and commit**

```bash
mint run swiftformat Spud/Scenes/PostDetail/Unavailable/PostUnavailableReason.swift Spud/Scenes/PostDetail/Unavailable/PostUnavailableViewController.swift SpudTests/PostUnavailableReasonTests.swift
make project   # new files
git add Spud/Scenes/PostDetail/Unavailable/PostUnavailableReason.swift Spud/Scenes/PostDetail/Unavailable/PostUnavailableViewController.swift SpudTests/PostUnavailableReasonTests.swift
git commit -m "feat: add PostUnavailable placeholder screen and gating reason"
```

---

### Task 7: Wire the placeholder into the detail flow

`.unavailable` state on the container; loading path fires it (fixes the infinite spinner); content path fires it via the header observation.

**Files:**
- Modify: `Spud/Scenes/PostDetail/PostDetailOrEmptyViewController.swift`
- Modify: `Spud/Scenes/PostDetail/Loading/PostDetailLoadingViewController.swift`
- Modify: `Spud/Scenes/PostDetail/Content/PostDetailViewController.swift` (header observation `:611-635`)

**Interfaces:**
- Consumes: `ContentNotFound.matchesPost` (Task 2); `PostUnavailableReason` + `PostUnavailableViewController` (Task 6); `PostDetailHeaderRow.isUnavailable` (Task 5); `moderationCapability.canModerate(communityId:)` and `viewModel.currentAccountPersonId` (existing).
- Produces: `PostDetailLoadingViewController.didFail: ((PostUnavailableReason) -> Void)?`; `PostDetailViewController.didBecomeUnavailable: ((PostUnavailableReason) -> Void)?`.

No new unit test — the pure logic (gating, classifier) is covered by Tasks 2 and 6; this task is view wiring, verified by build + the Task 8 snapshots + manual/verify. (Do NOT invent brittle VC-lifecycle unit tests.)

- [ ] **Step 1: Add the `.unavailable` state to the container**

In `PostDetailOrEmptyViewController.swift`, add to the `State` enum (`:50-54`):
```swift
        case unavailable(reason: PostUnavailableReason)
```
In `stateChanged()` add a case:
```swift
        case let .unavailable(reason):
            newViewController = PostUnavailableViewController(reason: reason)
```
In the `.load` case, after setting `didFinishLoading`, also wire the failure:
```swift
            loadingViewController.didFail = { [weak self] reason in
                self?.state = .unavailable(reason: reason)
            }
```
In the `.post` case, after building `contentViewController`, wire:
```swift
            contentViewController.didBecomeUnavailable = { [weak self] reason in
                self?.state = .unavailable(reason: reason)
            }
```

- [ ] **Step 2: Loading path fires `didFail` on not-found**

In `PostDetailLoadingViewController.swift`, add the callback near `didFinishLoading` (`:35`):
```swift
    /// Fires when the post cannot be loaded because the server reports it gone
    /// (`couldnt_find_post`). The parent swaps in the unavailable placeholder.
    var didFail: ((PostUnavailableReason) -> Void)?
```
Change `fetchPostInfo()` to report the not-found outcome and restructure `viewDidAppear`'s task:
```swift
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        observationTask?.cancel()
        observationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if await fetchPostInfoReportingNotFound() {
                didFail?(.unavailable)
                return
            }
            await notifyIfRowAvailable()
        }
    }

    /// Returns `true` when the post is gone server-side (`couldnt_find_post`);
    /// other errors are logged and return `false` (fall through to row check).
    private func fetchPostInfoReportingNotFound() async -> Bool {
        do {
            try await dependencies.own.accountService
                .scope(forAccountKeychainId: accountKeychainId)
                .lemmyService
                .fetchPostInfo(serverPostId: serverPostId)
            return false
        } catch {
            if ContentNotFound.matchesPost(error) { return true }
            alertService.handle(error, for: .fetchPostInfo)
            return false
        }
    }
```
Remove the old `fetchPostInfo()` method (replaced by `fetchPostInfoReportingNotFound()`). Add `import SpudDataKit` if not already present (it is).

- [ ] **Step 3: Content path fires `didBecomeUnavailable` from the header observation**

In `PostDetailViewController.swift`, add the property near the other callbacks (top of the class, alongside `headerRow` `:163`):
```swift
    /// Fires when the observed post flips to a gone state (removed / deleted by
    /// someone else / `couldnt_find_post`) and the current account is not a
    /// moderator or the author. The parent swaps in the unavailable placeholder.
    var didBecomeUnavailable: ((PostUnavailableReason) -> Void)?
```
In the header observation loop, right after `headerRow = row` (`:615`), add:
```swift
                if let row, let reason = unavailableReason(for: row) {
                    didBecomeUnavailable?(reason)
                    break
                }
```
And add the helper method:
```swift
    /// Maps an observed header row to the placeholder reason, or nil to keep the
    /// content. Mods keep removed posts; authors keep their own deleted posts.
    private func unavailableReason(for row: PostDetailHeaderRow) -> PostUnavailableReason? {
        let canModerate = moderationCapability.canModerate(
            communityId: Components.Schemas.CommunityID(row.serverCommunityId)
        )
        let isOwnPost = row.creatorPersonId == viewModel.currentAccountPersonId
        return PostUnavailableReason.forHeader(
            isRemoved: row.isRemoved,
            isDeleted: row.isDeleted,
            isUnavailable: row.isUnavailable,
            canModerate: canModerate,
            isOwnPost: isOwnPost
        )
    }
```
(`moderationCapability`, `viewModel.currentAccountPersonId`, and `row.serverCommunityId` already exist — see `postModerationMenu()` at `:1867` and `recordVisit` at `:647`.)

- [ ] **Step 4: Build to verify**

```bash
python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud
```
Expected: build succeeds, 0 new warnings. Then run the full detail-related unit set to confirm no regression:
```bash
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudTests -only-testing:SpudDataKitTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: PASS.

- [ ] **Step 5: Format and commit**

```bash
mint run swiftformat Spud/Scenes/PostDetail/PostDetailOrEmptyViewController.swift Spud/Scenes/PostDetail/Loading/PostDetailLoadingViewController.swift Spud/Scenes/PostDetail/Content/PostDetailViewController.swift
git add Spud/Scenes/PostDetail/PostDetailOrEmptyViewController.swift Spud/Scenes/PostDetail/Loading/PostDetailLoadingViewController.swift Spud/Scenes/PostDetail/Content/PostDetailViewController.swift
git commit -m "feat: show unavailable placeholder in post detail (loading + cached paths)"
```

---

### Task 8: Snapshots — placeholder + feed badge

**Files:**
- Create: `SpudSnapshotTests/PostUnavailableSnapshotTests.swift`
- Modify: `SpudSnapshotTests/PostListPostCellSnapshotTests.swift` (add an unavailable-badge case)

**Interfaces:**
- Consumes: `PostUnavailableViewController` (Task 6); `PostStatusBadge` + `PostListRow.isUnavailable` (Task 5).

- [ ] **Step 1: Write the placeholder snapshot test**

Create `SpudSnapshotTests/PostUnavailableSnapshotTests.swift`, one `assertSnapshot` per reason, using the device-independent `.image(on:)` config so any sim records deterministically (model on an existing `.image(on: .iPhone13Pro)` test in the suite):
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import XCTest
@testable import Spud

final class PostUnavailableSnapshotTests: XCTestCase {
    func test_unavailable() {
        let vc = PostUnavailableViewController(reason: .unavailable)
        assertSnapshot(of: vc, as: .image(on: .iPhone13Pro))
    }

    func test_removed() {
        let vc = PostUnavailableViewController(reason: .removed)
        assertSnapshot(of: vc, as: .image(on: .iPhone13Pro))
    }

    func test_deleted() {
        let vc = PostUnavailableViewController(reason: .deleted)
        assertSnapshot(of: vc, as: .image(on: .iPhone13Pro))
    }
}
```
For the feed cell: add a `test_unavailableBadge` to `PostListPostCellSnapshotTests.swift` modeled on its existing cases, building a `PostListRow` fixture with `isUnavailable: true` (and `isRemoved: false, isDeleted: false`).

- [ ] **Step 2: Record references (first run fails)**

Run the placeholder suite once to record, once to verify (see CLAUDE.md git-annex notes — record/verify one class at a time, never `git annex restage` between):
```bash
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan SpudSnapshots \
  -only-testing:SpudSnapshotTests/PostUnavailableSnapshotTests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: first run FAILS ("No reference" — refs written); rerun the same command → PASS. Repeat for `PostListPostCellSnapshotTests/test_unavailableBadge`.

- [ ] **Step 3: Verify + stage only the new refs**

Confirm the rerun is green. Stage ONLY the newly recorded PNGs by explicit path (never `git add …/__Snapshots__/` — it sweeps unrelated cosmetically-modified annex refs). Count with `find`, not `ls *.png`.

- [ ] **Step 4: Commit**

```bash
make project   # new snapshot test file
git add SpudSnapshotTests/PostUnavailableSnapshotTests.swift SpudSnapshotTests/PostListPostCellSnapshotTests.swift <explicit __Snapshots__/PostUnavailableSnapshotTests/*.png paths> <explicit new PostListPostCell ref path>
git commit -m "test: snapshots for unavailable placeholder and feed badge"
```

---

### Task 9: Feature documentation

**Files:**
- Create: `docs/features/removed-unavailable-content.md`
- Modify: `docs/features/README.md` (capability table + "Feature coverage by area" map)
- Modify (reconcile): `docs/features/empty-error-loading-states.md`, `docs/features/mark-read-and-hiding.md` (cross-link the new doc where they touch removed/hidden posts)

- [ ] **Step 1: Write the feature doc**

Create `docs/features/removed-unavailable-content.md` following `docs/features/_TEMPLATE.md`: a `## Capability` summary; `## Behavior and rules` (the three states — server-confirmed removed, server-confirmed deleted, ambiguous `couldnt_find_post`; the mod/author visibility gating; the neutral feed badge; automatic recovery on re-fetch); and `## Scenarios` as Given/When/Then covering: open a removed cached post (comment fetch 404s → placeholder); vote on a removed post from the feed (specific toast + neutral badge appears); deep-link to a removed post (placeholder, not an infinite spinner); moderator opens a removed post (still sees content + Restore); author opens own deleted post (still sees content + Restore); a later refresh restores the post (placeholder/badge clear). Set `Status:` and `Surfaces:` honestly. No `.swift` links.

- [ ] **Step 2: Update the README index**

In `docs/features/README.md`, add a row to the capability table and an entry in the "Feature coverage by area" map (both sections — they drift independently), pointing at `removed-unavailable-content.md`.

- [ ] **Step 3: Reconcile adjacent docs**

Add a one-line cross-link from `empty-error-loading-states.md` and `mark-read-and-hiding.md` to the new doc where they mention gone/hidden posts. Verify no adjacent doc now contradicts the new behavior.

- [ ] **Step 4: Commit**

```bash
git add docs/features/removed-unavailable-content.md docs/features/README.md docs/features/empty-error-loading-states.md docs/features/mark-read-and-hiding.md
git commit -m "docs: document removed/unavailable post handling"
```

---

## Final verification (after all tasks)

- [ ] Full unit suites green:
```bash
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test
```
- [ ] Snapshot suite green on the reference device:
```bash
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan SpudSnapshots \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1' \
  -skipPackagePluginValidation -skipMacroValidation test
```
- [ ] `mint run swiftformat --lint <all changed paths>` clean.
- [ ] Widget builds: `build_and_test.py --scheme SpudWidgetExtension`.
- [ ] Manual (device/sim): open the spam post from the report, confirm the placeholder replaces content; vote from the feed on a known-removed post, confirm "This post is no longer available" toast + neutral badge; deep-link a removed post id, confirm placeholder (no infinite spinner); as a mod, confirm removed posts still show content + Restore.

## Notes / accepted limitations

- Once the container is in `.unavailable`, there is no live observation to auto-recover if the post is restored while the screen is open; the user recovers by popping and re-opening (`resolveState` → row exists → content). Acceptable (rare).
- `getComments` may return an empty tree (no error) for some removed posts rather than `couldnt_find_post`; in that case the post reveals as gone only on the next `getPost`/vote. Expected — we detect at every touchpoint that surfaces the error, not more.
- `couldnt_find_post` is the confirmed code from the user's real log; if a Lemmy version surfaces post-not-found under a different structured code, add it to `ContentNotFound.postCodes` (Task 2) — the single edit point.
