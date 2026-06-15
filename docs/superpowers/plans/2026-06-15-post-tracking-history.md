# Post Tracking & New-Comment Delta — Implementation Plan (Phase 0 + Phase 1)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the local-only `postInteraction` foundation (records every post you open or see) and use it to flag comments that are new since you last opened a post.

**Architecture:** A single GRDB table `postInteraction`, keyed by `(accountId, postServerId)`, holding a denormalized snapshot plus seen/opened timestamps and counts. All mutation math lives in pure, unit-tested helpers (`PostInteractionUpdate`, `NewCommentState`); the `AppDatabase` storage methods are thin wrappers. Phase 1 reads the prior `lastOpenedAt` synchronously when a post detail opens, records the new visit, and computes which comments were published since the prior visit.

**Tech Stack:** Swift 6, GRDB, UIKit, XCTest. SpudDataKit framework (Swift 6.0 language mode) for the data layer; the Spud app target for the post-detail wiring.

**Scope note:** This plan covers spec Phase 0 (foundation) and Phase 1 (new-comment delta logic, wired into `PostDetailViewModel`). The per-comment *visual* marker, the header "N new" banner, and the jump-to-first-new affordance are deferred to the Claude Design pipeline (per the brainstorm decision to defer new-comment visuals) — this plan exposes the data the cells will read (`viewModel.newCommentCount`, `viewModel.isNewComment(elementId:)`, `viewModel.firstNewCommentElementId`). Spec Phase 2 (history + FTS search) and Phase 3 (seen-impression capture) are separate future plans; `recordPostSeen` is built here as foundation but has no caller yet.

**Build/test commands (run from `/Users/denis/dev/info.ddenis/Spud/Spud`):**

```sh
# Data-layer unit tests (most tasks). SpudDataKit is a framework scheme — pass an iOS simulator.
python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme SpudDataKit --simulator "iPhone 17 Pro"

# Full app build + unit tests (Phase 1 VM/VC tasks)
python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud --simulator "iPhone 17 Pro"

# Format before staging (pre-commit hook runs lint-only)
mint run swiftformat <changed-paths>
```

To run a single test class with xcodebuild:

```sh
xcodebuild -project Spud.xcodeproj -scheme Spud \
  -only-testing:SpudDataKitTests/PostInteractionUpdateTests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -skipPackagePluginValidation -skipMacroValidation test
```

---

## Task 1: `PostInteractionRecord` + `PostInteractionSnapshot`

**Files:**
- Create: `SpudDataKit/Services/AppDatabase/Records/PostInteraction.swift`
- Test: `SpudDataKitTests/PostInteractionRecordTests.swift`

- [ ] **Step 1: Write the failing test**

`SpudDataKitTests/PostInteractionRecordTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import XCTest
@testable import SpudDataKit

final class PostInteractionRecordTests: XCTestCase {
    func testConvenienceInitDefaultsAreEmpty() {
        let record = PostInteractionRecord(accountId: 7, postServerId: 42)
        XCTAssertNil(record.id)
        XCTAssertEqual(record.accountId, 7)
        XCTAssertEqual(record.postServerId, 42)
        XCTAssertNil(record.titleSnapshot)
        XCTAssertNil(record.firstSeenAt)
        XCTAssertNil(record.lastSeenAt)
        XCTAssertEqual(record.seenCount, 0)
        XCTAssertNil(record.lastOpenedAt)
        XCTAssertEqual(record.openedCount, 0)
        XCTAssertNil(record.lastKnownCommentCount)
    }

    func testApplySnapshotOverwritesSnapshotFields() {
        var record = PostInteractionRecord(accountId: 1, postServerId: 2)
        record.apply(PostInteractionSnapshot(
            titleSnapshot: "Hello",
            communityName: "tech",
            instanceHost: "lemmy.world",
            thumbnailUrl: "https://img.test/x.png",
            author: "alice"
        ))
        XCTAssertEqual(record.titleSnapshot, "Hello")
        XCTAssertEqual(record.communityName, "tech")
        XCTAssertEqual(record.instanceHost, "lemmy.world")
        XCTAssertEqual(record.thumbnailUrl, "https://img.test/x.png")
        XCTAssertEqual(record.author, "alice")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -only-testing:SpudDataKitTests/PostInteractionRecordTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation -skipMacroValidation test`
Expected: FAIL — "cannot find 'PostInteractionRecord' in scope".

- [ ] **Step 3: Write the implementation**

`SpudDataKit/Services/AppDatabase/Records/PostInteraction.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

/// Caller-provided render snapshot for a post interaction. Denormalized onto
/// the interaction row so history renders and searches without joining the
/// (possibly-evicted) `post` cache.
public struct PostInteractionSnapshot: Sendable, Equatable {
    public let titleSnapshot: String
    public let communityName: String
    public let instanceHost: String
    public let thumbnailUrl: String?
    public let author: String?

    public init(
        titleSnapshot: String,
        communityName: String,
        instanceHost: String,
        thumbnailUrl: String?,
        author: String?
    ) {
        self.titleSnapshot = titleSnapshot
        self.communityName = communityName
        self.instanceHost = instanceHost
        self.thumbnailUrl = thumbnailUrl
        self.author = author
    }
}

/// Local-only interaction log row. Records, per `(accountId, postServerId)`,
/// when a post was first/last seen on screen and last opened, plus a render
/// snapshot. Never synced to or mirrored from the server. `postServerId` is a
/// plain integer (not a foreign key) so a row survives `post` cache eviction.
public struct PostInteractionRecord: Codable, Sendable, Equatable, Identifiable {
    public static let databaseTableName = "postInteraction"

    public var id: Int64?
    public var accountId: Int64
    public var postServerId: Int64
    public var titleSnapshot: String?
    public var communityName: String?
    public var instanceHost: String?
    public var thumbnailUrl: String?
    public var author: String?
    public var firstSeenAt: Date?
    public var lastSeenAt: Date?
    public var seenCount: Int
    public var lastOpenedAt: Date?
    public var openedCount: Int
    public var lastKnownCommentCount: Int64?

    public init(
        id: Int64? = nil,
        accountId: Int64,
        postServerId: Int64,
        titleSnapshot: String? = nil,
        communityName: String? = nil,
        instanceHost: String? = nil,
        thumbnailUrl: String? = nil,
        author: String? = nil,
        firstSeenAt: Date? = nil,
        lastSeenAt: Date? = nil,
        seenCount: Int = 0,
        lastOpenedAt: Date? = nil,
        openedCount: Int = 0,
        lastKnownCommentCount: Int64? = nil
    ) {
        self.id = id
        self.accountId = accountId
        self.postServerId = postServerId
        self.titleSnapshot = titleSnapshot
        self.communityName = communityName
        self.instanceHost = instanceHost
        self.thumbnailUrl = thumbnailUrl
        self.author = author
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
        self.seenCount = seenCount
        self.lastOpenedAt = lastOpenedAt
        self.openedCount = openedCount
        self.lastKnownCommentCount = lastKnownCommentCount
    }

    /// Overwrites the denormalized snapshot fields from `snapshot`.
    public mutating func apply(_ snapshot: PostInteractionSnapshot) {
        titleSnapshot = snapshot.titleSnapshot
        communityName = snapshot.communityName
        instanceHost = snapshot.instanceHost
        thumbnailUrl = snapshot.thumbnailUrl
        author = snapshot.author
    }
}

extension PostInteractionRecord: FetchableRecord, MutablePersistableRecord {
    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run the Step 2 command. Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
mint run swiftformat SpudDataKit/Services/AppDatabase/Records/PostInteraction.swift SpudDataKitTests/PostInteractionRecordTests.swift
git add SpudDataKit/Services/AppDatabase/Records/PostInteraction.swift SpudDataKitTests/PostInteractionRecordTests.swift
git commit -m "feat: add PostInteractionRecord and snapshot type"
```

---

## Task 2: `v14_postInteraction` migration

**Files:**
- Modify: `SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift` (insert a new migration case immediately before `return migrator` at line 466)
- Test: `SpudDataKitTests/PostInteractionMigrationTests.swift`

- [ ] **Step 1: Write the failing test**

`SpudDataKitTests/PostInteractionMigrationTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import XCTest
@testable import SpudDataKit

final class PostInteractionMigrationTests: XCTestCase {
    func testPostInteractionTableExistsAfterMigration() throws {
        let appDatabase = try AppDatabase.inMemory()
        let exists = try appDatabase.writer.read { db in
            try db.tableExists("postInteraction")
        }
        XCTAssertTrue(exists)
    }

    func testUniqueOnAccountAndPostServerId() throws {
        let appDatabase = try AppDatabase.inMemory()
        try appDatabase.writer.write { db in
            try db.execute(sql: "INSERT INTO instance (actorId, createdAt) VALUES ('https://a.test', ?)", arguments: [Date()])
            let instanceId = db.lastInsertedRowID
            try db.execute(sql: "INSERT INTO site (instanceId, createdAt, updatedAt) VALUES (?, ?, ?)", arguments: [instanceId, Date(), Date()])
            let siteId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO account (siteId, accountKeychainId, isDefault, isServiceAccount, isSignedOutAccountType, createdAt, updatedAt)
                VALUES (?, 'kc-1', 0, 0, 0, ?, ?)
                """, arguments: [siteId, Date(), Date()])
            let accountId = db.lastInsertedRowID

            var first = PostInteractionRecord(accountId: accountId, postServerId: 100)
            try first.insert(db)
        }

        try appDatabase.writer.write { db in
            let accountId = try Int64.fetchOne(db, sql: "SELECT id FROM account LIMIT 1")!
            var duplicate = PostInteractionRecord(accountId: accountId, postServerId: 100)
            XCTAssertThrowsError(try duplicate.insert(db))
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -only-testing:SpudDataKitTests/PostInteractionMigrationTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation -skipMacroValidation test`
Expected: FAIL — `testPostInteractionTableExistsAfterMigration` fails (table missing).

- [ ] **Step 3: Add the migration**

In `SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift`, immediately before `return migrator` (currently line 466), add:

```swift
        migrator.registerMigration("v14_postInteraction") { db in
            // Local-only interaction log: when each post was first/last seen on
            // screen and last opened, plus a denormalized render snapshot. Never
            // synced. `postServerId` is a plain integer (not a FK) so a row
            // survives `post` cache eviction. Only `accountId` cascades.
            try db.create(table: "postInteraction") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("accountId", .integer)
                    .notNull()
                    .references("account", onDelete: .cascade)
                t.column("postServerId", .integer).notNull()
                t.column("titleSnapshot", .text)
                t.column("communityName", .text)
                t.column("instanceHost", .text)
                t.column("thumbnailUrl", .text)
                t.column("author", .text)
                t.column("firstSeenAt", .datetime)
                t.column("lastSeenAt", .datetime)
                t.column("seenCount", .integer).notNull().defaults(to: 0)
                t.column("lastOpenedAt", .datetime)
                t.column("openedCount", .integer).notNull().defaults(to: 0)
                t.column("lastKnownCommentCount", .integer)
                t.uniqueKey(["accountId", "postServerId"])
            }
            try db.create(
                index: "postInteraction_on_lastOpenedAt",
                on: "postInteraction",
                columns: ["lastOpenedAt"]
            )
            try db.create(
                index: "postInteraction_on_lastSeenAt",
                on: "postInteraction",
                columns: ["lastSeenAt"]
            )
        }
```

- [ ] **Step 4: Run test to verify it passes**

Run the Step 2 command. Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
mint run swiftformat SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift SpudDataKitTests/PostInteractionMigrationTests.swift
git add SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift SpudDataKitTests/PostInteractionMigrationTests.swift
git commit -m "feat: add v14 postInteraction migration"
```

---

## Task 3: `PostInteractionUpdate` pure helper

**Files:**
- Create: `SpudDataKit/Services/AppDatabase/PostInteractionUpdate.swift`
- Test: `SpudDataKitTests/PostInteractionUpdateTests.swift`

- [ ] **Step 1: Write the failing test**

`SpudDataKitTests/PostInteractionUpdateTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import XCTest
@testable import SpudDataKit

final class PostInteractionUpdateTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let t1 = Date(timeIntervalSince1970: 1_000_500)

    private func snapshot(_ title: String) -> PostInteractionSnapshot {
        PostInteractionSnapshot(
            titleSnapshot: title,
            communityName: "tech",
            instanceHost: "lemmy.world",
            thumbnailUrl: nil,
            author: "alice"
        )
    }

    // MARK: applyingOpen

    func testFirstOpenCreatesRowWithNilPrevious() {
        let (record, previous) = PostInteractionUpdate.applyingOpen(
            to: nil, accountId: 1, postServerId: 9, now: t0,
            commentCount: 12, snapshot: snapshot("Hello")
        )
        XCTAssertNil(previous)
        XCTAssertEqual(record.lastOpenedAt, t0)
        XCTAssertEqual(record.openedCount, 1)
        XCTAssertEqual(record.lastKnownCommentCount, 12)
        XCTAssertEqual(record.titleSnapshot, "Hello")
        XCTAssertEqual(record.seenCount, 0)
        XCTAssertNil(record.firstSeenAt)
    }

    func testSecondOpenReturnsPriorTimestampAndBumpsCount() {
        let (first, _) = PostInteractionUpdate.applyingOpen(
            to: nil, accountId: 1, postServerId: 9, now: t0,
            commentCount: 12, snapshot: snapshot("Hello")
        )
        let (second, previous) = PostInteractionUpdate.applyingOpen(
            to: first, accountId: 1, postServerId: 9, now: t1,
            commentCount: 15, snapshot: nil
        )
        XCTAssertEqual(previous, t0)
        XCTAssertEqual(second.lastOpenedAt, t1)
        XCTAssertEqual(second.openedCount, 2)
        XCTAssertEqual(second.lastKnownCommentCount, 15)
        // nil snapshot keeps the prior snapshot
        XCTAssertEqual(second.titleSnapshot, "Hello")
    }

    func testOpenWithNilCommentCountKeepsPriorCount() {
        let (first, _) = PostInteractionUpdate.applyingOpen(
            to: nil, accountId: 1, postServerId: 9, now: t0,
            commentCount: 12, snapshot: nil
        )
        let (second, _) = PostInteractionUpdate.applyingOpen(
            to: first, accountId: 1, postServerId: 9, now: t1,
            commentCount: nil, snapshot: nil
        )
        XCTAssertEqual(second.lastKnownCommentCount, 12)
    }

    // MARK: applyingSeen

    func testFirstSeenSetsBothTimestamps() {
        let record = PostInteractionUpdate.applyingSeen(
            to: nil, accountId: 1, postServerId: 9, now: t0, snapshot: snapshot("Hi")
        )
        XCTAssertEqual(record.firstSeenAt, t0)
        XCTAssertEqual(record.lastSeenAt, t0)
        XCTAssertEqual(record.seenCount, 1)
        XCTAssertEqual(record.openedCount, 0)
    }

    func testSecondSeenKeepsFirstSeenBumpsLast() {
        let first = PostInteractionUpdate.applyingSeen(
            to: nil, accountId: 1, postServerId: 9, now: t0, snapshot: snapshot("Hi")
        )
        let second = PostInteractionUpdate.applyingSeen(
            to: first, accountId: 1, postServerId: 9, now: t1, snapshot: snapshot("Hi")
        )
        XCTAssertEqual(second.firstSeenAt, t0)
        XCTAssertEqual(second.lastSeenAt, t1)
        XCTAssertEqual(second.seenCount, 2)
    }

    // MARK: shouldPrune

    func testSavedPostIsNeverPruned() {
        var record = PostInteractionRecord(accountId: 1, postServerId: 9)
        record.lastSeenAt = Date(timeIntervalSince1970: 0) // ancient
        let prune = PostInteractionUpdate.shouldPrune(
            record, now: t0, isSaved: true,
            seenRetention: 1, openedRetention: 1
        )
        XCTAssertFalse(prune)
    }

    func testOldSeenOnlyIsPruned() {
        var record = PostInteractionRecord(accountId: 1, postServerId: 9)
        record.lastSeenAt = t0
        let prune = PostInteractionUpdate.shouldPrune(
            record, now: t0.addingTimeInterval(40 * 86400), isSaved: false,
            seenRetention: PostInteractionUpdate.defaultSeenRetention,
            openedRetention: PostInteractionUpdate.defaultOpenedRetention
        )
        XCTAssertTrue(prune)
    }

    func testRecentSeenOnlyIsKept() {
        var record = PostInteractionRecord(accountId: 1, postServerId: 9)
        record.lastSeenAt = t0
        let prune = PostInteractionUpdate.shouldPrune(
            record, now: t0.addingTimeInterval(10 * 86400), isSaved: false,
            seenRetention: PostInteractionUpdate.defaultSeenRetention,
            openedRetention: PostInteractionUpdate.defaultOpenedRetention
        )
        XCTAssertFalse(prune)
    }

    func testOpenedUsesOpenedRetentionNotSeen() {
        // Opened 40 days ago: beyond the 30-day seen window but inside the
        // 1-year opened window, so it must be kept.
        var record = PostInteractionRecord(accountId: 1, postServerId: 9)
        record.lastOpenedAt = t0
        record.lastSeenAt = t0
        let prune = PostInteractionUpdate.shouldPrune(
            record, now: t0.addingTimeInterval(40 * 86400), isSaved: false,
            seenRetention: PostInteractionUpdate.defaultSeenRetention,
            openedRetention: PostInteractionUpdate.defaultOpenedRetention
        )
        XCTAssertFalse(prune)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -only-testing:SpudDataKitTests/PostInteractionUpdateTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation -skipMacroValidation test`
Expected: FAIL — "cannot find 'PostInteractionUpdate' in scope".

- [ ] **Step 3: Write the implementation**

`SpudDataKit/Services/AppDatabase/PostInteractionUpdate.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Pure, UIKit-free mutation math for `PostInteractionRecord`. Isolated from
/// storage so every counter/snapshot/retention rule is unit-tested without a
/// database.
public enum PostInteractionUpdate {
    /// Seen-only entries older than this are pruned. 30 days.
    public static let defaultSeenRetention: TimeInterval = 30 * 24 * 60 * 60
    /// Opened entries older than this are pruned. 365 days.
    public static let defaultOpenedRetention: TimeInterval = 365 * 24 * 60 * 60

    /// Applies an "opened" event. Returns the updated record and the
    /// `lastOpenedAt` value *before* this open (nil on a first-ever open) so the
    /// caller can compute the new-comment delta.
    public static func applyingOpen(
        to existing: PostInteractionRecord?,
        accountId: Int64,
        postServerId: Int64,
        now: Date,
        commentCount: Int64?,
        snapshot: PostInteractionSnapshot?
    ) -> (record: PostInteractionRecord, previousOpenedAt: Date?) {
        let previous = existing?.lastOpenedAt
        var record = existing ?? PostInteractionRecord(accountId: accountId, postServerId: postServerId)
        record.lastOpenedAt = now
        record.openedCount += 1
        if let commentCount {
            record.lastKnownCommentCount = commentCount
        }
        if let snapshot {
            record.apply(snapshot)
        }
        return (record, previous)
    }

    /// Applies a "seen on screen" event.
    public static func applyingSeen(
        to existing: PostInteractionRecord?,
        accountId: Int64,
        postServerId: Int64,
        now: Date,
        snapshot: PostInteractionSnapshot
    ) -> PostInteractionRecord {
        var record = existing ?? PostInteractionRecord(accountId: accountId, postServerId: postServerId)
        if record.firstSeenAt == nil {
            record.firstSeenAt = now
        }
        record.lastSeenAt = now
        record.seenCount += 1
        record.apply(snapshot)
        return record
    }

    /// Whether `record` should be deleted under the retention policy. Saved
    /// posts are exempt; opened entries use `openedRetention`; seen-only
    /// entries use `seenRetention`.
    public static func shouldPrune(
        _ record: PostInteractionRecord,
        now: Date,
        isSaved: Bool,
        seenRetention: TimeInterval,
        openedRetention: TimeInterval
    ) -> Bool {
        if isSaved {
            return false
        }
        if let lastOpenedAt = record.lastOpenedAt {
            return now.timeIntervalSince(lastOpenedAt) > openedRetention
        }
        guard let seenRef = record.lastSeenAt ?? record.firstSeenAt else {
            return false
        }
        return now.timeIntervalSince(seenRef) > seenRetention
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run the Step 2 command. Expected: PASS (9 tests).

- [ ] **Step 5: Commit**

```bash
mint run swiftformat SpudDataKit/Services/AppDatabase/PostInteractionUpdate.swift SpudDataKitTests/PostInteractionUpdateTests.swift
git add SpudDataKit/Services/AppDatabase/PostInteractionUpdate.swift SpudDataKitTests/PostInteractionUpdateTests.swift
git commit -m "feat: add PostInteractionUpdate pure mutation helper"
```

---

## Task 4: Storage methods (`recordPostOpened`, `recordPostSeen`, `prunePostInteractions`)

**Files:**
- Create: `SpudDataKit/Services/AppDatabase/PostInteractionWrites.swift`
- Test: `SpudDataKitTests/PostInteractionWritesTests.swift`

- [ ] **Step 1: Write the failing test**

`SpudDataKitTests/PostInteractionWritesTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import XCTest
@testable import SpudDataKit

final class PostInteractionWritesTests: XCTestCase {
    /// Seeds the minimal account graph (instance -> site -> account) and
    /// returns the account row id. `keychainId` lets multiple accounts coexist.
    @discardableResult
    private func seedAccount(_ appDatabase: AppDatabase, keychainId: String) throws -> Int64 {
        try appDatabase.writer.write { db in
            try db.execute(sql: "INSERT INTO instance (actorId, createdAt) VALUES (?, ?)", arguments: ["https://\(keychainId).test", Date()])
            let instanceId = db.lastInsertedRowID
            try db.execute(sql: "INSERT INTO site (instanceId, createdAt, updatedAt) VALUES (?, ?, ?)", arguments: [instanceId, Date(), Date()])
            let siteId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO account (siteId, accountKeychainId, isDefault, isServiceAccount, isSignedOutAccountType, createdAt, updatedAt)
                VALUES (?, ?, 0, 0, 0, ?, ?)
                """, arguments: [siteId, keychainId, Date(), Date()])
            return db.lastInsertedRowID
        }
    }

    private func fetchInteraction(_ appDatabase: AppDatabase, accountId: Int64, postServerId: Int64) throws -> PostInteractionRecord? {
        try appDatabase.writer.read { db in
            try PostInteractionRecord
                .filter(Column("accountId") == accountId)
                .filter(Column("postServerId") == postServerId)
                .fetchOne(db)
        }
    }

    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let t1 = Date(timeIntervalSince1970: 1_000_500)

    private func snapshot() -> PostInteractionSnapshot {
        PostInteractionSnapshot(titleSnapshot: "Hello", communityName: "tech", instanceHost: "lemmy.world", thumbnailUrl: nil, author: "alice")
    }

    func testRecordPostOpenedFirstThenSecondReturnsPrior() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let accountId = try seedAccount(appDatabase, keychainId: "kc-1")

        let first = try await appDatabase.recordPostOpened(
            accountKeychainId: "kc-1", serverPostId: 9, commentCount: 12, snapshot: snapshot(), now: t0
        )
        XCTAssertNil(first)

        let second = try await appDatabase.recordPostOpened(
            accountKeychainId: "kc-1", serverPostId: 9, commentCount: 15, snapshot: nil, now: t1
        )
        XCTAssertEqual(second, t0)

        let record = try XCTUnwrap(fetchInteraction(appDatabase, accountId: accountId, postServerId: 9))
        XCTAssertEqual(record.openedCount, 2)
        XCTAssertEqual(record.lastOpenedAt, t1)
        XCTAssertEqual(record.lastKnownCommentCount, 15)
        XCTAssertEqual(record.titleSnapshot, "Hello")
    }

    func testRecordPostOpenedUnknownAccountNoOps() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let result = try await appDatabase.recordPostOpened(
            accountKeychainId: "missing", serverPostId: 9, commentCount: nil, snapshot: nil, now: t0
        )
        XCTAssertNil(result)
    }

    func testRecordPostSeenAccumulates() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let accountId = try seedAccount(appDatabase, keychainId: "kc-1")

        try await appDatabase.recordPostSeen(accountKeychainId: "kc-1", serverPostId: 9, snapshot: snapshot(), now: t0)
        try await appDatabase.recordPostSeen(accountKeychainId: "kc-1", serverPostId: 9, snapshot: snapshot(), now: t1)

        let record = try XCTUnwrap(fetchInteraction(appDatabase, accountId: accountId, postServerId: 9))
        XCTAssertEqual(record.seenCount, 2)
        XCTAssertEqual(record.firstSeenAt, t0)
        XCTAssertEqual(record.lastSeenAt, t1)
    }

    func testPruneDeletesOldSeenKeepsRecentAndOpened() async throws {
        let appDatabase = try AppDatabase.inMemory()
        try seedAccount(appDatabase, keychainId: "kc-1")

        // Old seen-only (40 days ago) -> pruned.
        try await appDatabase.recordPostSeen(accountKeychainId: "kc-1", serverPostId: 1, snapshot: snapshot(), now: t0)
        // Recent seen-only (now) -> kept.
        let now = t0.addingTimeInterval(40 * 86400)
        try await appDatabase.recordPostSeen(accountKeychainId: "kc-1", serverPostId: 2, snapshot: snapshot(), now: now)
        // Opened 40 days ago -> kept (opened retention is 1 year).
        try await appDatabase.recordPostOpened(accountKeychainId: "kc-1", serverPostId: 3, commentCount: nil, snapshot: snapshot(), now: t0)

        let deleted = try await appDatabase.prunePostInteractions(now: now)
        XCTAssertEqual(deleted, 1)

        let accountId = try appDatabase.writer.read { db in try Int64.fetchOne(db, sql: "SELECT id FROM account LIMIT 1")! }
        XCTAssertNil(try fetchInteraction(appDatabase, accountId: accountId, postServerId: 1))
        XCTAssertNotNil(try fetchInteraction(appDatabase, accountId: accountId, postServerId: 2))
        XCTAssertNotNil(try fetchInteraction(appDatabase, accountId: accountId, postServerId: 3))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -only-testing:SpudDataKitTests/PostInteractionWritesTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation -skipMacroValidation test`
Expected: FAIL — "value of type 'AppDatabase' has no member 'recordPostOpened'".

- [ ] **Step 3: Write the implementation**

`SpudDataKit/Services/AppDatabase/PostInteractionWrites.swift`:

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
    /// Records that the post was opened. Resolves the account from
    /// `accountKeychainId`; no-ops (returns nil) if the account is unknown.
    /// Returns the `lastOpenedAt` value from *before* this open (nil on a
    /// first-ever open) for the new-comment delta.
    @discardableResult
    func recordPostOpened(
        accountKeychainId: String,
        serverPostId: Int64,
        commentCount: Int64?,
        snapshot: PostInteractionSnapshot?,
        now: Date = Date()
    ) async throws -> Date? {
        try await writer.write { db in
            guard let accountId = try Self.accountRowId(forKeychainId: accountKeychainId, in: db) else {
                return nil
            }
            let existing = try Self.interaction(accountId: accountId, postServerId: serverPostId, in: db)
            let (record, previous) = PostInteractionUpdate.applyingOpen(
                to: existing, accountId: accountId, postServerId: serverPostId,
                now: now, commentCount: commentCount, snapshot: snapshot
            )
            try Self.save(record, in: db)
            return previous
        }
    }

    /// Records that the post appeared on screen. Resolves the account from
    /// `accountKeychainId`; no-ops if the account is unknown.
    func recordPostSeen(
        accountKeychainId: String,
        serverPostId: Int64,
        snapshot: PostInteractionSnapshot,
        now: Date = Date()
    ) async throws {
        try await writer.write { db in
            guard let accountId = try Self.accountRowId(forKeychainId: accountKeychainId, in: db) else {
                return
            }
            let existing = try Self.interaction(accountId: accountId, postServerId: serverPostId, in: db)
            let record = PostInteractionUpdate.applyingSeen(
                to: existing, accountId: accountId, postServerId: serverPostId,
                now: now, snapshot: snapshot
            )
            try Self.save(record, in: db)
        }
    }

    /// Applies the retention policy. Saved posts are exempt. Returns the number
    /// of rows deleted.
    @discardableResult
    func prunePostInteractions(
        now: Date = Date(),
        seenRetention: TimeInterval = PostInteractionUpdate.defaultSeenRetention,
        openedRetention: TimeInterval = PostInteractionUpdate.defaultOpenedRetention
    ) async throws -> Int {
        try await writer.write { db in
            let records = try PostInteractionRecord.fetchAll(db)
            var deleted = 0
            for record in records {
                let isSaved = try Bool.fetchOne(
                    db,
                    sql: "SELECT isSaved FROM post WHERE accountId = ? AND postId = ?",
                    arguments: [record.accountId, record.postServerId]
                ) ?? false
                if PostInteractionUpdate.shouldPrune(
                    record, now: now, isSaved: isSaved,
                    seenRetention: seenRetention, openedRetention: openedRetention
                ) {
                    try record.delete(db)
                    deleted += 1
                }
            }
            return deleted
        }
    }

    // MARK: - Private helpers (run inside a database access closure)

    internal static func accountRowId(forKeychainId keychainId: String, in db: Database) throws -> Int64? {
        try AccountRecord
            .filter(Column("accountKeychainId") == keychainId)
            .fetchOne(db)?
            .id
    }

    internal static func interaction(accountId: Int64, postServerId: Int64, in db: Database) throws -> PostInteractionRecord? {
        try PostInteractionRecord
            .filter(Column("accountId") == accountId)
            .filter(Column("postServerId") == postServerId)
            .fetchOne(db)
    }

    internal static func save(_ record: PostInteractionRecord, in db: Database) throws {
        var record = record
        if record.id == nil {
            try record.insert(db)
        } else {
            try record.update(db)
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run the Step 2 command. Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
mint run swiftformat SpudDataKit/Services/AppDatabase/PostInteractionWrites.swift SpudDataKitTests/PostInteractionWritesTests.swift
git add SpudDataKit/Services/AppDatabase/PostInteractionWrites.swift SpudDataKitTests/PostInteractionWritesTests.swift
git commit -m "feat: add postInteraction storage writes and prune"
```

---

## Task 5: Sync query helpers (`lastOpenedAtSync`, `accountPersonServerIdSync`, `postInteractionSnapshotSync`)

**Files:**
- Create: `SpudDataKit/Services/AppDatabase/PostInteractionQueries.swift`
- Test: `SpudDataKitTests/PostInteractionQueriesTests.swift`

- [ ] **Step 1: Write the failing test**

`SpudDataKitTests/PostInteractionQueriesTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import XCTest
@testable import SpudDataKit

final class PostInteractionQueriesTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func snapshot() -> PostInteractionSnapshot {
        PostInteractionSnapshot(titleSnapshot: "Hello", communityName: "tech", instanceHost: "lemmy.world", thumbnailUrl: nil, author: "alice")
    }

    private func seedAccount(_ appDatabase: AppDatabase, keychainId: String, personServerId: Int64?) throws {
        try appDatabase.writer.write { db in
            try db.execute(sql: "INSERT INTO instance (actorId, createdAt) VALUES (?, ?)", arguments: ["https://\(keychainId).test", Date()])
            let instanceId = db.lastInsertedRowID
            try db.execute(sql: "INSERT INTO site (instanceId, createdAt, updatedAt) VALUES (?, ?, ?)", arguments: [instanceId, Date(), Date()])
            let siteId = db.lastInsertedRowID
            var personRowId: Int64?
            if let personServerId {
                try db.execute(sql: """
                    INSERT INTO person (siteId, personId, isAdmin, isBanned, isBotAccount, isDeleted, isLocal, numberOfPosts, numberOfComments, createdAt, updatedAt)
                    VALUES (?, ?, 0, 0, 0, 0, 0, 0, 0, ?, ?)
                    """, arguments: [siteId, personServerId, Date(), Date()])
                personRowId = db.lastInsertedRowID
            }
            try db.execute(sql: """
                INSERT INTO account (siteId, personId, accountKeychainId, isDefault, isServiceAccount, isSignedOutAccountType, createdAt, updatedAt)
                VALUES (?, ?, ?, 0, 0, 0, ?, ?)
                """, arguments: [siteId, personRowId, keychainId, Date(), Date()])
        }
    }

    func testLastOpenedAtSyncReturnsPriorValue() async throws {
        let appDatabase = try AppDatabase.inMemory()
        try seedAccount(appDatabase, keychainId: "kc-1", personServerId: nil)
        XCTAssertNil(appDatabase.lastOpenedAtSync(forKeychainId: "kc-1", serverPostId: 9))

        try await appDatabase.recordPostOpened(accountKeychainId: "kc-1", serverPostId: 9, commentCount: nil, snapshot: snapshot(), now: t0)
        XCTAssertEqual(appDatabase.lastOpenedAtSync(forKeychainId: "kc-1", serverPostId: 9), t0)
    }

    func testAccountPersonServerIdSync() throws {
        let appDatabase = try AppDatabase.inMemory()
        try seedAccount(appDatabase, keychainId: "kc-1", personServerId: 555)
        try seedAccount(appDatabase, keychainId: "kc-signedout", personServerId: nil)

        XCTAssertEqual(appDatabase.accountPersonServerIdSync(forKeychainId: "kc-1"), 555)
        XCTAssertNil(appDatabase.accountPersonServerIdSync(forKeychainId: "kc-signedout"))
        XCTAssertNil(appDatabase.accountPersonServerIdSync(forKeychainId: "missing"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -only-testing:SpudDataKitTests/PostInteractionQueriesTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation -skipMacroValidation test`
Expected: FAIL — "value of type 'AppDatabase' has no member 'lastOpenedAtSync'".

- [ ] **Step 3: Write the implementation**

`SpudDataKit/Services/AppDatabase/PostInteractionQueries.swift`:

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
    /// The `lastOpenedAt` recorded for `(account, post)` *before* the current
    /// open is written. Read synchronously during PostDetail bring-up so the
    /// new-comment delta has the prior-visit reference before `recordPostOpened`
    /// overwrites it. nil if never opened or the account/row is missing.
    func lastOpenedAtSync(forKeychainId keychainId: String, serverPostId: Int64) -> Date? {
        do {
            return try writer.read { db -> Date? in
                guard let accountId = try Self.accountRowId(forKeychainId: keychainId, in: db) else {
                    return nil
                }
                return try Self.interaction(accountId: accountId, postServerId: serverPostId, in: db)?.lastOpenedAt
            }
        } catch {
            logger.error("lastOpenedAtSync failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// The server-assigned person id for the account, used to exclude the
    /// user's own comments from the new-comment delta. nil for signed-out
    /// accounts (no linked person) or an unknown account.
    func accountPersonServerIdSync(forKeychainId keychainId: String) -> Int64? {
        do {
            return try writer.read { db -> Int64? in
                try Int64.fetchOne(db, sql: """
                    SELECT person.personId
                    FROM account
                    JOIN person ON person.id = account.personId
                    WHERE account.accountKeychainId = ?
                    """, arguments: [keychainId])
            }
        } catch {
            logger.error("accountPersonServerIdSync failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Builds an interaction snapshot (+ current comment count) from the cached
    /// `post` row, joining community + creator. nil if the post row is absent.
    /// `instanceHost` is derived from the community's federation actor id.
    func postInteractionSnapshotSync(postRowId: Int64) -> (snapshot: PostInteractionSnapshot, commentCount: Int64)? {
        do {
            return try writer.read { db -> (PostInteractionSnapshot, Int64)? in
                guard let row = try Row.fetchOne(db, sql: """
                        SELECT
                            post.title            AS title,
                            post.thumbnailUrl     AS thumbnailUrl,
                            post.numberOfComments AS numberOfComments,
                            community.name        AS communityName,
                            community.actorId     AS communityActorId,
                            creator.name          AS creatorName
                        FROM post
                        JOIN community ON community.id = post.communityId
                        JOIN person AS creator ON creator.id = post.creatorId
                        WHERE post.id = ?
                    """, arguments: [postRowId])
                else {
                    return nil
                }
                let communityActorId: String? = row["communityActorId"]
                let instanceHost = communityActorId.flatMap { URL(string: $0)?.host } ?? ""
                let snapshot = PostInteractionSnapshot(
                    titleSnapshot: row["title"] ?? "",
                    communityName: row["communityName"] ?? "",
                    instanceHost: instanceHost,
                    thumbnailUrl: row["thumbnailUrl"],
                    author: row["creatorName"]
                )
                let commentCount: Int64 = row["numberOfComments"] ?? 0
                return (snapshot, commentCount)
            }
        } catch {
            logger.error("postInteractionSnapshotSync failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run the Step 2 command. Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
mint run swiftformat SpudDataKit/Services/AppDatabase/PostInteractionQueries.swift SpudDataKitTests/PostInteractionQueriesTests.swift
git add SpudDataKit/Services/AppDatabase/PostInteractionQueries.swift SpudDataKitTests/PostInteractionQueriesTests.swift
git commit -m "feat: add postInteraction sync query helpers"
```

---

## Task 6: Run `prunePostInteractions` at launch

**Files:**
- Modify: `Spud/App/AppDelegate.swift:25` (after `coordinator.start()`)

No new automated test — this is a one-line launch wiring verified by the app build. (The prune logic itself is covered by Task 4.)

- [ ] **Step 1: Add the prune call**

In `Spud/App/AppDelegate.swift`, change the body of `didFinishLaunchingWithOptions` so it reads:

```swift
        coordinator.start()

        // Apply the local interaction-log retention policy in the background.
        // Best-effort: a failure just leaves old rows until the next launch.
        Task {
            try? await AppDatabase.shared.prunePostInteractions()
        }

        #if DEBUG
        SBTUITestTunnelServer.takeOff()
        #endif
        return true
```

Add the import at the top of the file if not present (after `import UIKit`):

```swift
import SpudDataKit
```

- [ ] **Step 2: Build the app to verify it compiles**

Run: `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud --simulator "iPhone 17 Pro"`
Expected: build succeeds; existing tests still pass.

- [ ] **Step 3: Commit**

```bash
mint run swiftformat Spud/App/AppDelegate.swift
git add Spud/App/AppDelegate.swift
git commit -m "feat: prune post interaction log at launch"
```

---

## Task 7: `NewCommentState` pure helper

**Files:**
- Create: `SpudDataKit/Services/AppDatabase/NewCommentState.swift`
- Test: `SpudDataKitTests/NewCommentStateTests.swift`

- [ ] **Step 1: Write the failing test**

`SpudDataKitTests/NewCommentStateTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import XCTest
@testable import SpudDataKit

final class NewCommentStateTests: XCTestCase {
    /// Builds a comment row with the fields the delta reads. `more: true`
    /// produces a "load more" placeholder (no serverCommentId / published).
    private func row(
        id: Int64,
        position: Int64,
        publishedOffset: TimeInterval,
        creatorPersonId: Int64 = 1,
        more: Bool = false
    ) -> PostDetailCommentRow {
        PostDetailCommentRow(
            id: id,
            position: position,
            depth: 1,
            serverCommentId: more ? nil : id,
            body: more ? nil : "body \(id)",
            originalCommentUrl: more ? nil : "https://example.test/comment/\(id)",
            score: 0,
            voteStatus: nil,
            isSaved: more ? nil : false,
            isRemoved: more ? nil : false,
            isDistinguished: more ? nil : false,
            isDeleted: more ? nil : false,
            isCreatorModerator: more ? nil : false,
            isCreatorAdmin: more ? nil : false,
            isCreatorBannedFromCommunity: more ? nil : false,
            isCreatorBlocked: more ? nil : false,
            isCreatorSiteBanned: more ? nil : false,
            isCreatorBot: more ? nil : false,
            isCreatorAccountDeleted: more ? nil : false,
            removedReason: nil,
            published: more ? nil : Date(timeIntervalSince1970: 1_000_000 + publishedOffset),
            creatorName: more ? nil : "u\(id)",
            creatorPersonId: more ? nil : creatorPersonId,
            creatorInstanceActorId: more ? nil : "https://example.test",
            moreChildCount: more ? 3 : nil,
            moreParentId: more ? 1 : nil
        )
    }

    private let visit = Date(timeIntervalSince1970: 1_000_000 + 100)

    func testFirstVisitNilReferenceFlagsNothing() {
        let rows = [row(id: 1, position: 1, publishedOffset: 200)]
        let result = NewCommentState.compute(orderedComments: rows, previousVisitAt: nil, currentAccountPersonId: nil)
        XCTAssertEqual(result.count, 0)
        XCTAssertNil(result.firstNewElementId)
    }

    func testCommentsAfterVisitAreNew() {
        let rows = [
            row(id: 1, position: 1, publishedOffset: 50),  // before visit
            row(id: 2, position: 2, publishedOffset: 150), // after visit
            row(id: 3, position: 3, publishedOffset: 300), // after visit
        ]
        let result = NewCommentState.compute(orderedComments: rows, previousVisitAt: visit, currentAccountPersonId: nil)
        XCTAssertEqual(result.newElementIds, [2, 3])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.firstNewElementId, 2)
    }

    func testOwnCommentsExcluded() {
        let rows = [
            row(id: 2, position: 2, publishedOffset: 150, creatorPersonId: 99), // mine
            row(id: 3, position: 3, publishedOffset: 300, creatorPersonId: 1),
        ]
        let result = NewCommentState.compute(orderedComments: rows, previousVisitAt: visit, currentAccountPersonId: 99)
        XCTAssertEqual(result.newElementIds, [3])
        XCTAssertEqual(result.firstNewElementId, 3)
    }

    func testLoadMorePlaceholdersIgnored() {
        let rows = [
            row(id: 5, position: 5, publishedOffset: 0, more: true), // no published
            row(id: 6, position: 6, publishedOffset: 300),
        ]
        let result = NewCommentState.compute(orderedComments: rows, previousVisitAt: visit, currentAccountPersonId: nil)
        XCTAssertEqual(result.newElementIds, [6])
    }

    func testFirstNewIsLowestPositionNotArrayOrder() {
        let rows = [
            row(id: 10, position: 9, publishedOffset: 300),
            row(id: 11, position: 4, publishedOffset: 300),
        ]
        let result = NewCommentState.compute(orderedComments: rows, previousVisitAt: visit, currentAccountPersonId: nil)
        XCTAssertEqual(result.firstNewElementId, 11)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -only-testing:SpudDataKitTests/NewCommentStateTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation -skipMacroValidation test`
Expected: FAIL — "cannot find 'NewCommentState' in scope".

- [ ] **Step 3: Write the implementation**

`SpudDataKit/Services/AppDatabase/NewCommentState.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Pure, UIKit-free computation of which comments are "new" since the user
/// last opened a post.
///
/// A comment is new iff: there is a prior-visit reference (`previousVisitAt`
/// non-nil — i.e. not the first-ever visit), it is a real comment (not a "load
/// more" placeholder), it was published strictly after `previousVisitAt`, and
/// it was not written by the current account. Comparison uses the comment's
/// `published` (creation) time, never `updated`, so edits don't re-flag.
public enum NewCommentState {
    public struct Result: Equatable, Sendable {
        /// `PostDetailCommentRow.id` (element id) of each new comment.
        public let newElementIds: Set<Int64>
        /// The new comment with the lowest display `position`, for
        /// "jump to first new". nil when there are none.
        public let firstNewElementId: Int64?

        public var count: Int { newElementIds.count }

        public init(newElementIds: Set<Int64>, firstNewElementId: Int64?) {
            self.newElementIds = newElementIds
            self.firstNewElementId = firstNewElementId
        }
    }

    public static func compute(
        orderedComments: [PostDetailCommentRow],
        previousVisitAt: Date?,
        currentAccountPersonId: Int64?
    ) -> Result {
        guard let previousVisitAt else {
            return Result(newElementIds: [], firstNewElementId: nil)
        }

        var newIds = Set<Int64>()
        var firstPosition: Int64?
        var firstId: Int64?

        for row in orderedComments {
            guard row.serverCommentId != nil, let published = row.published else {
                continue // "load more" placeholder
            }
            guard published > previousVisitAt else {
                continue
            }
            if let me = currentAccountPersonId, row.creatorPersonId == me {
                continue // the user's own comment
            }
            newIds.insert(row.id)
            if firstPosition == nil || row.position < firstPosition! {
                firstPosition = row.position
                firstId = row.id
            }
        }

        return Result(newElementIds: newIds, firstNewElementId: firstId)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run the Step 2 command. Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
mint run swiftformat SpudDataKit/Services/AppDatabase/NewCommentState.swift SpudDataKitTests/NewCommentStateTests.swift
git add SpudDataKit/Services/AppDatabase/NewCommentState.swift SpudDataKitTests/NewCommentStateTests.swift
git commit -m "feat: add NewCommentState delta helper"
```

---

## Task 8: Expose new-comment state on `PostDetailViewModel`

**Files:**
- Modify: `Spud/Scenes/PostDetail/Content/PostDetailViewModel.swift`
- Test: `SpudTests/PostDetailViewModelNewCommentTests.swift`

The view model gains the prior-visit reference, the current account's person id, and a recomputed `NewCommentState.Result`. The recompute happens inside the existing `updateOrderedComments(_:)`, so markers update whenever the comment observation emits.

- [ ] **Step 1: Write the failing test**

`SpudTests/PostDetailViewModelNewCommentTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudDataKit
import XCTest
@testable import Spud

@MainActor
final class PostDetailViewModelNewCommentTests: XCTestCase {
    private func makeRow(id: Int64, publishedOffset: TimeInterval, creatorPersonId: Int64 = 1) -> PostDetailCommentRow {
        PostDetailCommentRow(
            id: id, position: id, depth: 1,
            serverCommentId: id, body: "b\(id)",
            originalCommentUrl: "https://example.test/comment/\(id)",
            score: 0, voteStatus: nil, isSaved: false, isRemoved: false,
            isDistinguished: false, isDeleted: false, isCreatorModerator: false,
            isCreatorAdmin: false, isCreatorBannedFromCommunity: false,
            isCreatorBlocked: false, isCreatorSiteBanned: false, isCreatorBot: false,
            isCreatorAccountDeleted: false, removedReason: nil,
            published: Date(timeIntervalSince1970: 1_000_000 + publishedOffset),
            creatorName: "u\(id)", creatorPersonId: creatorPersonId,
            creatorInstanceActorId: "https://example.test",
            moreChildCount: nil, moreParentId: nil
        )
    }

    private func makeViewModel() -> PostDetailViewModel {
        PostDetailViewModel(
            serverPostId: 1,
            accountKeychainId: "kc-1",
            dependencies: TestDependencies()
        )
    }

    func testNoPriorVisitFlagsNothing() {
        let vm = makeViewModel()
        vm.previousVisitAt = nil
        vm.updateOrderedComments([makeRow(id: 1, publishedOffset: 500)])
        XCTAssertEqual(vm.newCommentCount, 0)
        XCTAssertFalse(vm.isNewComment(elementId: 1))
        XCTAssertNil(vm.firstNewCommentElementId)
    }

    func testFlagsCommentsAfterPriorVisit() {
        let vm = makeViewModel()
        vm.previousVisitAt = Date(timeIntervalSince1970: 1_000_000 + 100)
        vm.currentAccountPersonId = nil
        vm.updateOrderedComments([
            makeRow(id: 1, publishedOffset: 50),
            makeRow(id: 2, publishedOffset: 300),
        ])
        XCTAssertEqual(vm.newCommentCount, 1)
        XCTAssertTrue(vm.isNewComment(elementId: 2))
        XCTAssertFalse(vm.isNewComment(elementId: 1))
        XCTAssertEqual(vm.firstNewCommentElementId, 2)
    }

    func testOwnCommentExcluded() {
        let vm = makeViewModel()
        vm.previousVisitAt = Date(timeIntervalSince1970: 1_000_000 + 100)
        vm.currentAccountPersonId = 99
        vm.updateOrderedComments([makeRow(id: 5, publishedOffset: 300, creatorPersonId: 99)])
        XCTAssertEqual(vm.newCommentCount, 0)
    }
}
```

This test references a `TestDependencies` type satisfying `PostDetailViewModel.Dependencies` (`HasAccountService & HasAlertService & HasPreferencesService`). If `SpudTests` already has a shared test-dependencies fixture, use it instead and delete the stub below. Otherwise add this minimal stub in the same file (above the test class), wiring real service instances against an in-memory database:

```swift
private struct TestDependencies:
    HasAccountService, HasAlertService, HasPreferencesService
{
    let accountService: AccountServiceType
    let alertService: AlertServiceType
    let preferencesService: PreferencesServiceType

    init() {
        let appDatabase = try! AppDatabase.inMemory()
        accountService = AccountService(appDatabase: appDatabase)
        alertService = AlertService()
        preferencesService = PreferencesService()
    }
}
```

> If these service initializers differ in this codebase, adjust to match how `SpudSnapshotTests` constructs them (the project notes describe snapshotting a VC "by passing a fake struct conforming to its `Dependencies` composition (e.g. `StaticImageService()` + `AlertService()` + `AccountService(appDatabase: try AppDatabase.inMemory())`)"). The new-comment assertions do not touch these services — they only need the VM to initialize.

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -only-testing:SpudTests/PostDetailViewModelNewCommentTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation -skipMacroValidation test`
Expected: FAIL — `value of type 'PostDetailViewModel' has no member 'previousVisitAt'`.

- [ ] **Step 3: Modify the view model**

In `Spud/Scenes/PostDetail/Content/PostDetailViewModel.swift`:

(a) After the `collapsedElementIds` declaration (currently ends line 46), add the prior-visit inputs and the computed delta state:

```swift
    /// The `lastOpenedAt` from before this visit, used to flag comments
    /// published since. nil on a first-ever visit (nothing is "new"). Set once
    /// by the view controller during observation bring-up.
    @ObservationIgnored
    var previousVisitAt: Date?

    /// The current account's server person id, used to exclude the user's own
    /// comments from the new-comment delta. nil when signed out.
    @ObservationIgnored
    var currentAccountPersonId: Int64?

    /// Which comments are new since `previousVisitAt`. Recomputed on every
    /// comment-tree snapshot. Observable so the header count updates.
    private(set) var newCommentState: NewCommentState.Result =
        .init(newElementIds: [], firstNewElementId: nil)
```

(b) In `updateOrderedComments(_:)` (currently lines 76-80), recompute the delta after storing the rows. Replace the method body with:

```swift
    func updateOrderedComments(_ rows: [PostDetailCommentRow]) {
        orderedComments = rows
        let existingIds = Set(rows.map(\.id))
        collapsedElementIds.formIntersection(existingIds)
        newCommentState = NewCommentState.compute(
            orderedComments: rows,
            previousVisitAt: previousVisitAt,
            currentAccountPersonId: currentAccountPersonId
        )
    }
```

(c) Add the read accessors. Insert after `isCollapsed(elementId:)` (currently ends line 97):

```swift
    // MARK: - New-comment delta (view-layer)

    /// Number of comments new since the user's last visit.
    var newCommentCount: Int {
        newCommentState.count
    }

    /// Whether the comment element `elementId` is new since the last visit.
    func isNewComment(elementId: Int64) -> Bool {
        newCommentState.newElementIds.contains(elementId)
    }

    /// The element id of the first (lowest-position) new comment, for
    /// "jump to first new". nil when there are none.
    var firstNewCommentElementId: Int64? {
        newCommentState.firstNewElementId
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run the Step 2 command. Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
mint run swiftformat Spud/Scenes/PostDetail/Content/PostDetailViewModel.swift SpudTests/PostDetailViewModelNewCommentTests.swift
git add Spud/Scenes/PostDetail/Content/PostDetailViewModel.swift SpudTests/PostDetailViewModelNewCommentTests.swift
git commit -m "feat: expose new-comment delta on PostDetailViewModel"
```

---

## Task 9: Record the open and capture the prior visit in `PostDetailViewController`

**Files:**
- Modify: `Spud/Scenes/PostDetail/Content/PostDetailViewController.swift:316-344` (the `startObservations()` method)

This records the visit (independent of the `markPostsRead` preference, which only controls the server `markAsRead` round-trip) and seeds the VM's `previousVisitAt` / `currentAccountPersonId` *synchronously* before the comment observation emits, so the first comment snapshot already has the correct delta.

No new automated test (UIKit bring-up wiring; the logic underneath is covered by Tasks 5/7/8). Verified by the app build + existing post-detail tests.

- [ ] **Step 1: Add the recording to `startObservations()`**

In `Spud/Scenes/PostDetail/Content/PostDetailViewController.swift`, inside `startObservations()`, after the `guard let postRowId = ... else { ... }` block (currently ends line 331) and before `observationTask = Task { ... }` (currently line 333), insert:

```swift
        recordVisit(keychainId: keychainId, serverPostId: serverPostId, postRowId: postRowId)
```

Then add the new private method below `startObservations()` (after its closing brace, currently line 344):

```swift
    /// Records this post-detail visit in the local interaction log and seeds
    /// the view model's new-comment delta inputs. The prior `lastOpenedAt` is
    /// read synchronously *before* the async write overwrites it, so the first
    /// comment snapshot already reflects the correct "new since last visit"
    /// set. Recording is independent of `markPostsRead` (that preference only
    /// gates the server `markAsRead` round-trip).
    private func recordVisit(keychainId: String, serverPostId: Int64, postRowId: Int64) {
        viewModel.previousVisitAt = appDatabase.lastOpenedAtSync(
            forKeychainId: keychainId,
            serverPostId: serverPostId
        )
        viewModel.currentAccountPersonId = appDatabase.accountPersonServerIdSync(
            forKeychainId: keychainId
        )

        let snapshotAndCount = appDatabase.postInteractionSnapshotSync(postRowId: postRowId)
        Task { [appDatabase] in
            try? await appDatabase.recordPostOpened(
                accountKeychainId: keychainId,
                serverPostId: serverPostId,
                commentCount: snapshotAndCount?.commentCount,
                snapshot: snapshotAndCount?.snapshot
            )
        }
    }
```

> Note: `keychainId` and `serverPostId` are already local constants in `startObservations()` (lines 319-320: `let keychainId = viewModel.accountKeychainId` and `let serverPostId = Int64(viewModel.serverPostId)`).

- [ ] **Step 2: Build the app and run post-detail tests**

Run: `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud --simulator "iPhone 17 Pro"`
Expected: build succeeds; the full unit-test plan (including `SpudDataKitTests` from Tasks 1-7 and `SpudTests` from Task 8) passes.

- [ ] **Step 3: Manual smoke check (optional but recommended)**

Open a post with comments, leave, wait, have a new comment appear (or use a seeded test instance — see the workspace `lemmy-test-instances` notes), reopen the post. Confirm `viewModel.newCommentCount > 0` via a breakpoint or temporary log. (The visible marker/banner is the deferred Claude Design follow-up.)

- [ ] **Step 4: Commit**

```bash
mint run swiftformat Spud/Scenes/PostDetail/Content/PostDetailViewController.swift
git add Spud/Scenes/PostDetail/Content/PostDetailViewController.swift
git commit -m "feat: record post visit and seed new-comment delta on open"
```

---

## Done criteria

- `postInteraction` table exists (migration v14) and survives `post` cache eviction (no FK on `postServerId`).
- Opening a post records `lastOpenedAt` + snapshot + comment count, and bumps `openedCount`, regardless of the `markPostsRead` preference.
- `recordPostSeen` and the retention `prune` are implemented and unit-tested (no UI caller yet — Phase 3).
- Reopening a post computes the correct set of comments published since the prior open, excluding the user's own comments and "load more" placeholders, exposed via `viewModel.newCommentCount` / `isNewComment(elementId:)` / `firstNewCommentElementId`.
- Prune runs at app launch.
- All new unit tests pass; the app builds clean.

## Deferred to follow-up plans

- **Per-comment visual marker + "N new" header banner + jump-to-first-new button** — Claude Design pipeline, consuming the VM accessors added in Task 8.
- **Phase 2: History surface + FTS search** (account/profile area; adds the FTS index over `titleSnapshot`/`communityName`).
- **Phase 3: Seen-impression capture** (feed cell dwell detection calling `recordPostSeen`).
- **Phase 4: Push notifications** (background polling on `lastKnownCommentCount`; add `pushMuted`).
