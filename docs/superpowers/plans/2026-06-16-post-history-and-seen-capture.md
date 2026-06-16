# Post History, Search & Seen-Capture — Implementation Plan (Phase 2 + Phase 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a searchable **History** screen (Phase 2) over the local `postInteraction` log, and capture **seen-on-screen** impressions from the feed (Phase 3) so History/search covers posts you scrolled past, not just ones you opened.

**Architecture:** Phase 2 adds an FTS5 full-text index over the `postInteraction` snapshot (kept in sync by GRDB's `synchronize(withTable:)`), a `observeHistoryRows` observation that INNER JOINs `postInteraction → post → community → person` and emits the existing `PostListRow` type, and a dedicated `HistoryViewController` that REUSES the feed's `PostListPostCell`/`PostListPostViewModel` (no degraded rows — posts are never evicted in Spud, so the join always matches). Phase 3 instruments the feed's cell-display lifecycle with a dwell timer to call the already-built `recordPostSeen`.

**Tech Stack:** Swift 6, GRDB (SQLite FTS5, available in system SQLite on iOS 18), UIKit (UITableViewDiffableDataSource, UISearchController), XCTest. SpudDataKit for data; the Spud app target for the scene + feed instrumentation.

**Builds on the shipped Phase 0/1 foundation:** `postInteraction` table (migration v14) with columns `id, accountId, postServerId, titleSnapshot, communityName, instanceHost, thumbnailUrl, author, firstSeenAt, lastSeenAt, seenCount, lastOpenedAt, openedCount, lastKnownCommentCount`; `recordPostSeen(accountKeychainId:serverPostId:snapshot:now:)` (built, currently no caller — Phase 3 is its caller); `PostInteractionSnapshot`. Internal `AppDatabase` helpers `accountRowId(forKeychainId:in:)` and `interaction(accountId:postServerId:in:)` exist in `PostInteractionWrites.swift`.

**Design decisions (confirmed / from the approved spec):**
- Search: **FTS5** over `titleSnapshot`, `communityName`, `author`.
- History rows: **reuse the feed `PostListPostCell`** via the existing `PostListRow` + `PostListPostViewModel`. Because Spud has no post-eviction path (verified: only an account delete removes posts, which cascades the interaction rows too), an INNER JOIN always finds the post — no degraded/snapshot-only rendering needed.
- History is a **dedicated scene** (`HistoryViewController`), not a `FeedType`/`PostListViewController` reuse (that VC is built around server cursor pagination, which History does not have).
- One segmented control — **Read / Seen / Saved** (this consolidates the spec's "Recently Read/Seen segment" + "All seen/Only opened/Saved scope" into one clear control; the search field filters within the active segment):
  - **Read**: `lastOpenedAt IS NOT NULL`, newest-opened first.
  - **Seen**: every interaction row (everything encountered), most-recently-encountered first.
  - **Saved**: joined `post.isSaved = 1`, most-recently-encountered first. (Overlaps the existing server "Saved" feed but is local + searchable; confirm at review whether to keep.)
- Entry point: a **"History"** button in the account/profile footer next to "Saved".
- Phase 3 dwell threshold ≈ **500ms**, on cells that are displayed (UIKit `willDisplay`/`didEndDisplaying`), writes batched.

**Commands (run from `/Users/denis/dev/info.ddenis/Spud/Spud`):**

```sh
# Data-layer tests (Phase 2 Tasks 1-2, Phase 3 Task 7). iPhone 17 is the booted sim.
xcodebuild -project Spud.xcodeproj -scheme Spud -only-testing:SpudDataKitTests/<Class> \
  -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -skipMacroValidation test

# App build + full unit plan (UI tasks)
python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud --simulator "iPhone 17"

# After creating ANY new .swift file: regenerate the project (sources are globbed by project.yml)
make project
```

House rules for every task: XcodeGen regen (`make project`) after creating new files; booted `iPhone 17` only (don't boot a second sim); Swift 6 strict concurrency; no emojis; `mint run swiftformat <paths>` before staging; stage explicit paths only (never `git add -A`; `git status -uall` to see new files); never touch `.remember/remember.md` or `SpudSnapshotTests/__Snapshots__/`; end each commit message with a blank line then `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. Ignore SourceKit "No such module" editor diagnostics — trust the build.

---

# Phase 2 — History + FTS search

## Task 1: FTS5 index over `postInteraction` (migration v15)

**Files:**
- Modify: `SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift` (append a new migration before `return migrator`)
- Modify: `SpudDataKitTests/AppDatabaseTests.swift` (the table-set assertion in `testMigratorCreatesAllExpectedTables`)
- Test: `SpudDataKitTests/PostInteractionFtsTests.swift`

- [ ] **Step 1: Write the failing test**

`SpudDataKitTests/PostInteractionFtsTests.swift`:

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

final class PostInteractionFtsTests: XCTestCase {
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

    /// Inserts an interaction row directly and returns its id.
    private func insertInteraction(_ appDatabase: AppDatabase, accountId: Int64, postServerId: Int64, title: String) throws -> Int64 {
        try appDatabase.writer.write { db in
            var record = PostInteractionRecord(accountId: accountId, postServerId: postServerId)
            record.titleSnapshot = title
            record.communityName = "programming"
            record.author = "alice"
            try record.insert(db)
            return record.id!
        }
    }

    /// Helper: count FTS matches for a query, joined back to postInteraction.
    private func matchCount(_ appDatabase: AppDatabase, _ query: String) throws -> Int {
        try appDatabase.writer.read { db in
            guard let pattern = FTS5Pattern(matchingAllTokensIn: query) else { return 0 }
            return try Int.fetchOne(db, sql: """
                SELECT count(*) FROM postInteraction
                JOIN postInteractionFts ON postInteractionFts.rowid = postInteraction.id
                WHERE postInteractionFts MATCH ?
                """, arguments: [pattern]) ?? 0
        }
    }

    func testFtsTableExists() throws {
        let appDatabase = try AppDatabase.inMemory()
        let exists = try appDatabase.writer.read { db in try db.tableExists("postInteractionFts") }
        XCTAssertTrue(exists)
    }

    func testInsertIsIndexedAndSearchable() throws {
        let appDatabase = try AppDatabase.inMemory()
        let accountId = try seedAccount(appDatabase, keychainId: "kc-1")
        _ = try insertInteraction(appDatabase, accountId: accountId, postServerId: 1, title: "Swift Concurrency explained")

        XCTAssertEqual(try matchCount(appDatabase, "concurrency"), 1)
        XCTAssertEqual(try matchCount(appDatabase, "programming"), 1) // communityName indexed
        XCTAssertEqual(try matchCount(appDatabase, "rust"), 0)
    }

    func testUpdateAndDeleteStayInSync() throws {
        let appDatabase = try AppDatabase.inMemory()
        let accountId = try seedAccount(appDatabase, keychainId: "kc-1")
        let id = try insertInteraction(appDatabase, accountId: accountId, postServerId: 1, title: "Swift Concurrency")

        // Update the indexed title; old token gone, new token present.
        try appDatabase.writer.write { db in
            try db.execute(sql: "UPDATE postInteraction SET titleSnapshot = ? WHERE id = ?", arguments: ["Rust ownership", id])
        }
        XCTAssertEqual(try matchCount(appDatabase, "concurrency"), 0)
        XCTAssertEqual(try matchCount(appDatabase, "ownership"), 1)

        // Delete; no matches remain.
        try appDatabase.writer.write { db in
            try db.execute(sql: "DELETE FROM postInteraction WHERE id = ?", arguments: [id])
        }
        XCTAssertEqual(try matchCount(appDatabase, "ownership"), 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -only-testing:SpudDataKitTests/PostInteractionFtsTests -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -skipMacroValidation test` (run `make project` first — new test file).
Expected: FAIL — `testFtsTableExists` fails (no `postInteractionFts` table).

- [ ] **Step 3: Add the migration**

In `SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift`, immediately before `return migrator`, add:

```swift
        migrator.registerMigration("v15_postInteractionFts") { db in
            // Full-text index over the interaction snapshot, for History search.
            // `synchronize(withTable:)` creates the INSERT/UPDATE/DELETE triggers
            // that keep the FTS index in lockstep with `postInteraction` and
            // backfills any existing rows. External-content FTS5 (content rows
            // live in `postInteraction`; the index stores only the tokens).
            try db.create(virtualTable: "postInteractionFts", using: FTS5()) { t in
                t.synchronize(withTable: "postInteraction")
                t.tokenizer = .unicode61()
                t.column("titleSnapshot")
                t.column("communityName")
                t.column("author")
            }
        }
```

- [ ] **Step 3b: Update the migrator table-set test**

`SpudDataKitTests/AppDatabaseTests.swift` `testMigratorCreatesAllExpectedTables` asserts the exact set of app tables. Creating the FTS5 virtual table also creates several shadow tables (`postInteractionFts_data`, `_idx`, `_content`, `_docsize`, `_config`). The existing assertion filters out `grdb_`/`sqlite_` prefixes but NOT these. Update the filter to also drop FTS shadow tables, and add the virtual table name itself. Change the `appTables` filter line to:

```swift
        let appTables = tableNames.filter {
            !$0.hasPrefix("grdb_") && !$0.hasPrefix("sqlite_") && !$0.hasPrefix("postInteractionFts_")
        }
```

and add `"postInteractionFts"` to the expected `Set` (alphabetically, after `"postInteraction"`):

```swift
                "postInteraction",
                "postInteractionFts",
                "site",
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -only-testing:SpudDataKitTests/PostInteractionFtsTests -only-testing:SpudDataKitTests/AppDatabaseTests -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -skipMacroValidation test`
Expected: PASS (PostInteractionFtsTests 3 + AppDatabaseTests all). If `AppDatabaseTests` still fails on the table set, inspect the actual `tableNames` it prints and adjust the filter/expected set to match exactly what FTS5 created (the shadow-table names above are the standard FTS5 set; the prefix filter should cover them).

- [ ] **Step 5: Commit**

```bash
mint run swiftformat SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift SpudDataKitTests/PostInteractionFtsTests.swift SpudDataKitTests/AppDatabaseTests.swift
git add SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift SpudDataKitTests/PostInteractionFtsTests.swift SpudDataKitTests/AppDatabaseTests.swift
git commit -m "feat: add v15 FTS5 index over postInteraction snapshot"
```

---

## Task 2: `observeHistoryRows` observation + `HistoryMode`

**Files:**
- Create: `SpudDataKit/Services/AppDatabase/HistoryObservations.swift`
- Test: `SpudDataKitTests/HistoryObservationsTests.swift`

This emits the existing `PostListRow` (reused verbatim) so the History scene can drive the feed cell. INNER JOIN `postInteraction → post → community → person`. `HistoryMode` selects the filter + ordering; an optional FTS query narrows results.

- [ ] **Step 1: Write the failing test**

`SpudDataKitTests/HistoryObservationsTests.swift`:

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

final class HistoryObservationsTests: XCTestCase {
    /// Seeds account + community + creator person and returns the account row id.
    private func seedGraph(_ db: Database, keychainId: String) throws -> (accountId: Int64, communityId: Int64, personId: Int64) {
        try db.execute(sql: "INSERT INTO instance (actorId, createdAt) VALUES (?, ?)", arguments: ["https://\(keychainId).test", Date()])
        let instanceId = db.lastInsertedRowID
        try db.execute(sql: "INSERT INTO site (instanceId, createdAt, updatedAt) VALUES (?, ?, ?)", arguments: [instanceId, Date(), Date()])
        let siteId = db.lastInsertedRowID
        try db.execute(sql: """
            INSERT INTO person (siteId, personId, name, isAdmin, isBanned, isBotAccount, isDeleted, isLocal, numberOfPosts, numberOfComments, createdAt, updatedAt)
            VALUES (?, 10, 'alice', 0, 0, 0, 0, 0, 0, 0, ?, ?)
            """, arguments: [siteId, Date(), Date()])
        let personId = db.lastInsertedRowID
        try db.execute(sql: """
            INSERT INTO account (siteId, accountKeychainId, isDefault, isServiceAccount, isSignedOutAccountType, createdAt, updatedAt)
            VALUES (?, ?, 0, 0, 0, ?, ?)
            """, arguments: [siteId, keychainId, Date(), Date()])
        let accountId = db.lastInsertedRowID
        try db.execute(sql: """
            INSERT INTO community (accountId, communityId, name, actorId, isHidden, isLocal, isNsfw, isPostingRestrictedToMods, isRemoved, subscribedState, numberOfSubscribers, numberOfPosts, numberOfComments, createdAt, updatedAt)
            VALUES (?, 5, 'programming', 'https://\(keychainId).test/c/programming', 0, 0, 0, 0, 0, 'NotSubscribed', 0, 0, 0, ?, ?)
            """, arguments: [accountId, Date(), Date()])
        let communityId = db.lastInsertedRowID
        return (accountId, communityId, personId)
    }

    /// Inserts a post (and returns its row id) for the given account/community/creator.
    private func insertPost(_ db: Database, accountId: Int64, communityId: Int64, personId: Int64, serverPostId: Int64, title: String, isSaved: Bool) throws -> Int64 {
        try db.execute(sql: """
            INSERT INTO post (accountId, communityId, creatorId, postId, title, originalPostUrl, score, numberOfUpvotes, numberOfDownvotes, numberOfComments, isRead, isSaved, isHidden, isRemoved, isLocked, isFeaturedCommunity, isFeaturedLocal, isDeleted, published, createdAt, updatedAt)
            VALUES (?, ?, ?, ?, ?, 'https://x.test/post/\(serverPostId)', 7, 7, 0, 3, 0, ?, 0, 0, 0, 0, 0, 0, ?, ?, ?)
            """, arguments: [accountId, communityId, personId, serverPostId, title, isSaved, Date(), Date(), Date()])
        return db.lastInsertedRowID
    }

    private func insertInteraction(_ db: Database, accountId: Int64, postServerId: Int64, title: String, lastOpenedAt: Date?, lastSeenAt: Date?) throws {
        var record = PostInteractionRecord(accountId: accountId, postServerId: postServerId)
        record.titleSnapshot = title
        record.communityName = "programming"
        record.lastOpenedAt = lastOpenedAt
        record.lastSeenAt = lastSeenAt
        try record.insert(db)
    }

    private func firstBatch(_ stream: AsyncStream<[PostListRow]>) async -> [PostListRow] {
        for await rows in stream { return rows }
        return []
    }

    private let t1 = Date(timeIntervalSince1970: 1_000_100)
    private let t2 = Date(timeIntervalSince1970: 1_000_200)

    func testReadModeReturnsOnlyOpenedNewestFirst() async throws {
        let appDatabase = try AppDatabase.inMemory()
        try appDatabase.writer.write { db in
            let g = try seedGraph(db, keychainId: "kc-1")
            _ = try insertPost(db, accountId: g.accountId, communityId: g.communityId, personId: g.personId, serverPostId: 1, title: "Opened earlier", isSaved: false)
            _ = try insertPost(db, accountId: g.accountId, communityId: g.communityId, personId: g.personId, serverPostId: 2, title: "Opened later", isSaved: false)
            _ = try insertPost(db, accountId: g.accountId, communityId: g.communityId, personId: g.personId, serverPostId: 3, title: "Only seen", isSaved: false)
            try insertInteraction(db, accountId: g.accountId, postServerId: 1, title: "Opened earlier", lastOpenedAt: t1, lastSeenAt: nil)
            try insertInteraction(db, accountId: g.accountId, postServerId: 2, title: "Opened later", lastOpenedAt: t2, lastSeenAt: nil)
            try insertInteraction(db, accountId: g.accountId, postServerId: 3, title: "Only seen", lastOpenedAt: nil, lastSeenAt: t1)
        }
        let rows = await firstBatch(appDatabase.observeHistoryRows(forKeychainId: "kc-1", mode: .read, searchQuery: nil))
        XCTAssertEqual(rows.map(\.serverPostId), [2, 1]) // newest opened first; "only seen" excluded
    }

    func testSeenModeReturnsEverythingEncountered() async throws {
        let appDatabase = try AppDatabase.inMemory()
        try appDatabase.writer.write { db in
            let g = try seedGraph(db, keychainId: "kc-1")
            _ = try insertPost(db, accountId: g.accountId, communityId: g.communityId, personId: g.personId, serverPostId: 1, title: "Opened", isSaved: false)
            _ = try insertPost(db, accountId: g.accountId, communityId: g.communityId, personId: g.personId, serverPostId: 3, title: "Only seen", isSaved: false)
            try insertInteraction(db, accountId: g.accountId, postServerId: 1, title: "Opened", lastOpenedAt: t1, lastSeenAt: nil)
            try insertInteraction(db, accountId: g.accountId, postServerId: 3, title: "Only seen", lastOpenedAt: nil, lastSeenAt: t2)
        }
        let rows = await firstBatch(appDatabase.observeHistoryRows(forKeychainId: "kc-1", mode: .seen, searchQuery: nil))
        XCTAssertEqual(Set(rows.map(\.serverPostId)), [1, 3])
        XCTAssertEqual(rows.first?.serverPostId, 3) // most-recently-encountered first (t2 > t1)
    }

    func testSavedModeReturnsOnlySaved() async throws {
        let appDatabase = try AppDatabase.inMemory()
        try appDatabase.writer.write { db in
            let g = try seedGraph(db, keychainId: "kc-1")
            _ = try insertPost(db, accountId: g.accountId, communityId: g.communityId, personId: g.personId, serverPostId: 1, title: "Saved one", isSaved: true)
            _ = try insertPost(db, accountId: g.accountId, communityId: g.communityId, personId: g.personId, serverPostId: 2, title: "Unsaved", isSaved: false)
            try insertInteraction(db, accountId: g.accountId, postServerId: 1, title: "Saved one", lastOpenedAt: t1, lastSeenAt: nil)
            try insertInteraction(db, accountId: g.accountId, postServerId: 2, title: "Unsaved", lastOpenedAt: t2, lastSeenAt: nil)
        }
        let rows = await firstBatch(appDatabase.observeHistoryRows(forKeychainId: "kc-1", mode: .saved, searchQuery: nil))
        XCTAssertEqual(rows.map(\.serverPostId), [1])
    }

    func testSearchNarrowsByTitle() async throws {
        let appDatabase = try AppDatabase.inMemory()
        try appDatabase.writer.write { db in
            let g = try seedGraph(db, keychainId: "kc-1")
            _ = try insertPost(db, accountId: g.accountId, communityId: g.communityId, personId: g.personId, serverPostId: 1, title: "Swift Concurrency", isSaved: false)
            _ = try insertPost(db, accountId: g.accountId, communityId: g.communityId, personId: g.personId, serverPostId: 2, title: "Rust ownership", isSaved: false)
            try insertInteraction(db, accountId: g.accountId, postServerId: 1, title: "Swift Concurrency", lastOpenedAt: t1, lastSeenAt: nil)
            try insertInteraction(db, accountId: g.accountId, postServerId: 2, title: "Rust ownership", lastOpenedAt: t2, lastSeenAt: nil)
        }
        let rows = await firstBatch(appDatabase.observeHistoryRows(forKeychainId: "kc-1", mode: .seen, searchQuery: "concurrency"))
        XCTAssertEqual(rows.map(\.serverPostId), [1])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run (after `make project`): `xcodebuild -project Spud.xcodeproj -scheme Spud -only-testing:SpudDataKitTests/HistoryObservationsTests -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -skipMacroValidation test`
Expected: FAIL — `value of type 'AppDatabase' has no member 'observeHistoryRows'` / no `HistoryMode`.

- [ ] **Step 3: Write the implementation**

`SpudDataKit/Services/AppDatabase/HistoryObservations.swift`:

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

/// Which slice of the local interaction history to show.
public enum HistoryMode: Sendable, CaseIterable {
    /// Posts the user opened, newest-opened first.
    case read
    /// Every post the user encountered (opened or merely seen on screen),
    /// most-recently-encountered first.
    case seen
    /// Encountered posts that are currently saved, most-recently-encountered first.
    case saved
}

public extension AppDatabase {
    /// Stream of History rows for the account, reusing the feed `PostListRow`
    /// type so the History screen can drive the existing post cell. INNER JOINs
    /// `postInteraction -> post -> community -> person` (a post is never evicted
    /// while its account exists, so the join always matches). `searchQuery`, when
    /// non-empty, narrows via the FTS5 index over the interaction snapshot.
    func observeHistoryRows(
        forKeychainId keychainId: String,
        mode: HistoryMode,
        searchQuery: String?
    ) -> AsyncStream<[PostListRow]> {
        // Most-recently-encountered ordering: the larger of the two timestamps,
        // NULLs coalesced to '' (which sorts before any real timestamp text).
        let encounteredExpr = "max(coalesce(postInteraction.lastSeenAt, ''), coalesce(postInteraction.lastOpenedAt, ''))"
        let (modeWhere, orderBy): (String, String)
        switch mode {
        case .read:
            modeWhere = "AND postInteraction.lastOpenedAt IS NOT NULL"
            orderBy = "postInteraction.lastOpenedAt DESC"
        case .seen:
            modeWhere = ""
            orderBy = "\(encounteredExpr) DESC"
        case .saved:
            modeWhere = "AND post.isSaved = 1"
            orderBy = "\(encounteredExpr) DESC"
        }

        let trimmed = searchQuery?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasSearch = !(trimmed?.isEmpty ?? true)

        let observation = ValueObservation
            .tracking { [hasSearch, modeWhere, orderBy, trimmed] db -> [PostListRow] in
                guard let accountId = try Self.accountRowId(forKeychainId: keychainId, in: db) else {
                    return []
                }

                var sql = """
                    SELECT
                        post.id                AS postRowId,
                        post.postId            AS serverPostId,
                        post.title             AS title,
                        post.body              AS body,
                        post.originalPostUrl   AS originalPostUrl,
                        post.url               AS url,
                        post.thumbnailUrl      AS thumbnailUrl,
                        post.urlEmbedTitle     AS urlEmbedTitle,
                        post.urlEmbedDescription AS urlEmbedDescription,
                        post.altText           AS altText,
                        post.score             AS score,
                        post.numberOfComments  AS numberOfComments,
                        post.voteStatus        AS voteStatus,
                        post.isRead            AS isRead,
                        post.isSaved           AS isSaved,
                        post.isRemoved         AS isRemoved,
                        post.isLocked          AS isLocked,
                        post.isFeaturedCommunity AS isFeaturedCommunity,
                        post.isFeaturedLocal   AS isFeaturedLocal,
                        post.isDeleted         AS isDeleted,
                        post.published         AS published,
                        community.communityId  AS serverCommunityId,
                        community.name         AS communityName,
                        community.actorId      AS communityActorId,
                        creator.personId       AS creatorPersonId,
                        creator.name           AS creatorName,
                        creator.actorId        AS creatorActorId
                    FROM postInteraction
                    JOIN post      ON post.accountId = postInteraction.accountId AND post.postId = postInteraction.postServerId
                    JOIN community ON community.id = post.communityId
                    JOIN person    AS creator ON creator.id = post.creatorId
                """

                var arguments: [DatabaseValueConvertible] = []
                if hasSearch, let trimmed, let pattern = FTS5Pattern(matchingAllTokensIn: trimmed) {
                    sql += "\nJOIN postInteractionFts ON postInteractionFts.rowid = postInteraction.id AND postInteractionFts MATCH ?"
                    arguments.append(pattern)
                }
                sql += "\nWHERE postInteraction.accountId = ? \(modeWhere)"
                arguments.append(accountId)
                sql += "\nORDER BY \(orderBy)"

                let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
                return rows.map { row in
                    PostListRow(
                        id: row["postRowId"],
                        serverPostId: row["serverPostId"],
                        title: row["title"],
                        body: row["body"],
                        originalPostUrl: row["originalPostUrl"] ?? "",
                        url: row["url"],
                        thumbnailUrl: row["thumbnailUrl"],
                        urlEmbedTitle: row["urlEmbedTitle"],
                        urlEmbedDescription: row["urlEmbedDescription"],
                        altText: row["altText"],
                        communityName: row["communityName"] ?? "",
                        communityActorId: row["communityActorId"],
                        serverCommunityId: row["serverCommunityId"],
                        creatorPersonId: row["creatorPersonId"],
                        creatorName: row["creatorName"],
                        creatorActorId: row["creatorActorId"],
                        score: row["score"],
                        numberOfComments: row["numberOfComments"],
                        voteStatus: row["voteStatus"],
                        isRead: row["isRead"],
                        isSaved: row["isSaved"],
                        isRemoved: row["isRemoved"],
                        isLocked: row["isLocked"],
                        isFeaturedCommunity: row["isFeaturedCommunity"],
                        isFeaturedLocal: row["isFeaturedLocal"],
                        isDeleted: row["isDeleted"],
                        published: row["published"]
                    )
                }
            }
            .removeDuplicates()

        return AsyncStream { continuation in
            let cancellable = observation.start(in: writer, scheduling: .async(onQueue: .global(qos: .userInitiated))) { error in
                logger.error("History ValueObservation failed: \(String(describing: error), privacy: .public)")
                continuation.finish()
            } onChange: { value in
                continuation.yield(value)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run the Step 2 command. Expected: PASS (4 tests). If the `.seen` ordering assertion is flaky on text-timestamp comparison, confirm GRDB stores `Date` as the lexicographically-sortable `"yyyy-MM-dd HH:mm:ss.SSS"` string (it does by default) — the `max(coalesce(...))` expression relies on that.

- [ ] **Step 5: Commit**

```bash
mint run swiftformat SpudDataKit/Services/AppDatabase/HistoryObservations.swift SpudDataKitTests/HistoryObservationsTests.swift
git add SpudDataKit/Services/AppDatabase/HistoryObservations.swift SpudDataKitTests/HistoryObservationsTests.swift
git commit -m "feat: add observeHistoryRows + HistoryMode"
```

---

## Task 3: `HistoryViewModel`

**Files:**
- Create: `Spud/Scenes/History/HistoryViewModel.swift`
- Test: `SpudTests/HistoryViewModelTests.swift`

A small `@MainActor @Observable` view model holding the current `HistoryMode` and search text. It does not own the observation (the VC starts/restarts the stream when `mode`/`searchText` change) — it just holds state and exposes the current query inputs, mirroring how `PostListViewModel` holds `accountKeychainId` + light state.

- [ ] **Step 1: Write the failing test**

`SpudTests/HistoryViewModelTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import XCTest
@testable import Spud

@MainActor
final class HistoryViewModelTests: XCTestCase {
    func testDefaultsToReadModeAndEmptySearch() {
        let vm = HistoryViewModel(accountKeychainId: "kc-1")
        XCTAssertEqual(vm.mode, .read)
        XCTAssertNil(vm.searchQuery)
    }

    func testSearchTextNormalizesToNilWhenBlank() {
        let vm = HistoryViewModel(accountKeychainId: "kc-1")
        vm.searchText = "  "
        XCTAssertNil(vm.searchQuery)
        vm.searchText = "  swift "
        XCTAssertEqual(vm.searchQuery, "swift")
    }

    func testModeIsMutable() {
        let vm = HistoryViewModel(accountKeychainId: "kc-1")
        vm.mode = .saved
        XCTAssertEqual(vm.mode, .saved)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run (after `make project`): `xcodebuild -project Spud.xcodeproj -scheme Spud -only-testing:SpudTests/HistoryViewModelTests -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -skipMacroValidation test`
Expected: FAIL — `cannot find 'HistoryViewModel' in scope`.

- [ ] **Step 3: Write the implementation**

`Spud/Scenes/History/HistoryViewModel.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Observation
import SpudDataKit

/// View-model state for HistoryViewController. Holds the active history mode and
/// the search text; the view controller observes these and (re)starts the GRDB
/// history stream when they change.
@MainActor
@Observable
final class HistoryViewModel {
    @ObservationIgnored
    let accountKeychainId: String

    var mode: HistoryMode = .read

    /// Raw text from the search bar. `searchQuery` is the normalized form fed to
    /// the observation.
    var searchText: String = ""

    /// Trimmed search text, or nil when blank (no search filter).
    var searchQuery: String? {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    init(accountKeychainId: String) {
        self.accountKeychainId = accountKeychainId
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run the Step 2 command. Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
mint run swiftformat Spud/Scenes/History/HistoryViewModel.swift SpudTests/HistoryViewModelTests.swift
git add Spud/Scenes/History/HistoryViewModel.swift SpudTests/HistoryViewModelTests.swift
git commit -m "feat: add HistoryViewModel"
```

---

## Task 4: `HistoryViewController` (reuses the feed cell)

**Files:**
- Create: `Spud/Scenes/History/HistoryViewController.swift`
- Reference (read, do not modify): `Spud/Scenes/PostList/PostListViewController.swift` (the diffable data source setup, cell-provider closure, `didSelectRowAt`/`postSelected`, and the `for await rows in appDatabase.observe...` consumption pattern), `Spud/Scenes/PostList/PostListPostCell.swift`, `Spud/Scenes/PostList/PostListPostViewModel.swift` (its initializer), `Spud/Scenes/MainWindow/MainWindow.swift` (`display(serverPostId:accountKeychainId:)`).

This task has no isolated unit test (UIKit scene). Verification is the app build + a snapshot test is optional. Mirror `PostListViewController`'s structure closely; the differences are: data source comes from `observeHistoryRows` (not a feed), there is a segmented control + search controller, and there is no pagination/pull-to-refresh.

- [ ] **Step 1: Implement the view controller**

Create `Spud/Scenes/History/HistoryViewController.swift`. Requirements (match the cited reference patterns exactly):

1. **Dependencies:** reuse the same composition `PostListViewController` uses so the cell can be built and a post can be opened:
   ```swift
   typealias OwnDependencies =
       HasAccountService &
       HasAppDatabase &
       HasAppearanceService &
       HasImageService &
       HasPostContentDetectorService &
       HasPreferencesService
   typealias NestedDependencies = PostDetailViewController.Dependencies
   typealias Dependencies = OwnDependencies & NestedDependencies
   ```
   (Confirm the exact set against `PostListViewController.Dependencies`; drop `HasAlertService` if History performs no actions that surface alerts — it does not vote/save here. Include whatever `PostListPostViewModel(...)` and `MainWindow.display` transitively require.)

2. **Init:** `init(accountKeychainId: String, dependencies: Dependencies)`, build `HistoryViewModel(accountKeychainId:)`.

3. **Table + cell:** a `UITableView` (plain), register `PostListPostCell.self` with `PostListPostCell.reuseIdentifier`. Use `UITableViewDiffableDataSource<Section, Item>` with `enum Section { case posts }` and `enum Item: Hashable { case post(serverPostId: Int64) }`. The cell-provider closure builds the cell exactly like `PostListViewController` does:
   ```swift
   guard case let .post(serverPostId) = itemIdentifier,
         let row = self.rowsByServerPostId[serverPostId] else { return UITableViewCell() }
   let cell = tableView.dequeueReusableCell(withIdentifier: PostListPostCell.reuseIdentifier, for: indexPath) as! PostListPostCell
   let viewModel = PostListPostViewModel(row: row, appearance: self.appearance, postContentDetector: self.postContentDetector)
   cell.configure(with: viewModel, imageService: self.imageService)
   return cell
   ```
   (Copy the exact `appearance`/`postContentDetector`/`imageService` accessors and the `PostListPostViewModel(...)` argument labels from `PostListViewController` — match them verbatim.)

4. **Segmented control:** a `UISegmentedControl` with segments Read / Seen / Saved (localized), placed in the navigation bar `titleView` or as a table header. On `.valueChanged`, set `viewModel.mode` to the matching `HistoryMode` and restart the observation (Step: `startObservation()`).

5. **Search:** a `UISearchController` with its `searchResultsUpdater` (or the search bar delegate) writing `viewModel.searchText`, debounced ~250ms, then restart the observation. Set `navigationItem.searchController` and `navigationItem.hidesSearchBarWhenScrolling = false`.

6. **Observation:** a `startObservation()` method that cancels any prior task and starts a new one:
   ```swift
   observationTask?.cancel()
   observationTask = Task { @MainActor [weak self] in
       guard let self else { return }
       for await rows in appDatabase.observeHistoryRows(
           forKeychainId: viewModel.accountKeychainId,
           mode: viewModel.mode,
           searchQuery: viewModel.searchQuery
       ) {
           if Task.isCancelled { break }
           rowsByServerPostId = Dictionary(uniqueKeysWithValues: rows.map { ($0.serverPostId, $0) })
           applySnapshot(order: rows.map(\.serverPostId))
       }
   }
   ```
   `applySnapshot(order:)` builds an `NSDiffableDataSourceSnapshot` with `.post(serverPostId:)` items in the given order. Start the observation in `viewDidLoad` and after each mode/search change. Show an empty-state label when `rows.isEmpty`.

7. **Tap → open post:** mirror `PostListViewController.postSelected`:
   ```swift
   func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
       tableView.deselectRow(at: indexPath, animated: true)
       guard case let .post(serverPostId) = dataSource.itemIdentifier(for: indexPath) else { return }
       guard let window = view.window as? MainWindow else { return }
       window.display(serverPostId: Components.Schemas.PostID(serverPostId), accountKeychainId: viewModel.accountKeychainId)
   }
   ```

8. **Title:** `navigationItem.title = NSLocalizedString("History", comment: "History screen title")`.

- [ ] **Step 2: Build to verify it compiles**

Run `make project` then `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud --simulator "iPhone 17"`.
Expected: build succeeds; existing tests still pass.

- [ ] **Step 3: Commit**

```bash
mint run swiftformat Spud/Scenes/History/HistoryViewController.swift
git add Spud/Scenes/History/HistoryViewController.swift
git commit -m "feat: add HistoryViewController reusing the feed post cell"
```

---

## Task 5: Account entry point ("History" button)

**Files:**
- Modify: `Spud/Scenes/Account/AccountActionsFooterView.swift`
- Modify: `Spud/Scenes/Account/AccountViewController.swift` (wire the callback + push `HistoryViewController`, next to the existing Saved flow at `openSaved`)

No isolated unit test — build-verified.

- [ ] **Step 1: Add the History button to the footer**

In `Spud/Scenes/Account/AccountActionsFooterView.swift`:

(a) Add the callback alongside `savedTapped`:
```swift
    var historyTapped: (() -> Void)?
```

(b) Add the button (place it between Saved and Log out), mirroring `savedButton`:
```swift
    private lazy var historyButton = makeButton(
        title: NSLocalizedString("History", comment: "Account footer: open browsing history"),
        systemImage: "clock.arrow.circlepath",
        action: #selector(didTapHistory)
    )
```

(c) Include it in the stack — change the stack construction in `setup()`:
```swift
        let stack = UIStackView(arrangedSubviews: [savedButton, historyButton, logoutButton])
```

(d) Add the action:
```swift
    @objc
    private func didTapHistory() {
        historyTapped?()
    }
```

- [ ] **Step 2: Wire the callback in `AccountViewController`**

In `Spud/Scenes/Account/AccountViewController.swift`, where the footer's `savedTapped` is wired (search `footer.savedTapped`), add an analogous `footer.historyTapped` that calls a new `openHistory(keychainId:)`. Add the method next to `openSaved(keychainId:)`:

```swift
    private func openHistory(keychainId: String) {
        Haptics.tap()
        let historyVC = HistoryViewController(
            accountKeychainId: keychainId,
            dependencies: dependencies.nested
        )
        navigationController?.pushViewController(historyVC, animated: true)
    }
```

(Confirm `dependencies.nested` provides everything `HistoryViewController.Dependencies` needs — it is the same nested composition used to build `PostListViewController` in `openSaved`. If `HistoryViewController.Dependencies` is a strict subset of `PostListViewController.Dependencies`, `dependencies.nested` satisfies it; if it needs a peer dependency the account scene doesn't expose, widen `AccountViewController`'s own `Dependencies` to include it and pass through — mirror how `openSaved` obtains `dependencies.nested`.)

- [ ] **Step 3: Build + smoke**

Run `make project` then `build_and_test.py --scheme Spud --simulator "iPhone 17"`. Expected: build succeeds, tests green. (Optional manual: sign in, open Account, tap History — the screen pushes and lists recently-read posts.)

- [ ] **Step 4: Commit**

```bash
mint run swiftformat Spud/Scenes/Account/AccountActionsFooterView.swift Spud/Scenes/Account/AccountViewController.swift
git add Spud/Scenes/Account/AccountActionsFooterView.swift Spud/Scenes/Account/AccountViewController.swift
git commit -m "feat: add History entry point to the account footer"
```

---

# Phase 3 — Seen-impression capture (feeds)

## Task 6: Pure helpers — dwell tracking + snapshot mapping

**Files:**
- Create: `SpudDataKit/Services/AppDatabase/PostInteractionSnapshot+PostListRow.swift`
- Create: `Spud/Scenes/PostList/SeenDwellTracker.swift`
- Test: `SpudDataKitTests/PostInteractionSnapshotMappingTests.swift`
- Test: `SpudTests/SeenDwellTrackerTests.swift`

Isolate the two testable bits of Phase 3 so the VC wiring (Task 7) stays thin: (a) build a `PostInteractionSnapshot` from a `PostListRow`; (b) a pure dwell tracker that decides which posts have been on screen long enough.

- [ ] **Step 1: Write the failing tests**

`SpudDataKitTests/PostInteractionSnapshotMappingTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import XCTest
@testable import SpudDataKit

final class PostInteractionSnapshotMappingTests: XCTestCase {
    private func row(communityActorId: String?) -> PostListRow {
        PostListRow(
            id: 1, serverPostId: 9, title: "Hello", body: nil,
            originalPostUrl: "https://lemmy.world/post/9", url: nil, thumbnailUrl: "https://img.test/t.png",
            urlEmbedTitle: nil, urlEmbedDescription: nil, altText: nil,
            communityName: "programming", communityActorId: communityActorId, serverCommunityId: 5,
            creatorPersonId: 10, creatorName: "alice", creatorActorId: "https://lemmy.world/u/alice",
            score: 7, numberOfComments: 3, voteStatus: nil, isRead: false, isSaved: false,
            isRemoved: false, isLocked: false, isFeaturedCommunity: false, isFeaturedLocal: false,
            isDeleted: false, published: Date(timeIntervalSince1970: 0)
        )
    }

    func testMapsFieldsAndDerivesInstanceHost() {
        let snap = PostInteractionSnapshot(postListRow: row(communityActorId: "https://lemmy.world/c/programming"))
        XCTAssertEqual(snap.titleSnapshot, "Hello")
        XCTAssertEqual(snap.communityName, "programming")
        XCTAssertEqual(snap.instanceHost, "lemmy.world")
        XCTAssertEqual(snap.thumbnailUrl, "https://img.test/t.png")
        XCTAssertEqual(snap.author, "alice")
    }

    func testInstanceHostEmptyWhenActorIdMissing() {
        let snap = PostInteractionSnapshot(postListRow: row(communityActorId: nil))
        XCTAssertEqual(snap.instanceHost, "")
    }
}
```

`SpudTests/SeenDwellTrackerTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import XCTest
@testable import Spud

final class SeenDwellTrackerTests: XCTestCase {
    private let threshold: TimeInterval = 0.5
    private let t0 = Date(timeIntervalSince1970: 1000)

    func testAppearThenDisappearPastThresholdIsSeen() {
        var tracker = SeenDwellTracker(threshold: threshold)
        tracker.didAppear(serverPostId: 1, at: t0)
        let seen = tracker.didDisappear(serverPostId: 1, at: t0.addingTimeInterval(0.6))
        XCTAssertEqual(seen, 1)
    }

    func testDisappearBeforeThresholdIsNotSeen() {
        var tracker = SeenDwellTracker(threshold: threshold)
        tracker.didAppear(serverPostId: 1, at: t0)
        let seen = tracker.didDisappear(serverPostId: 1, at: t0.addingTimeInterval(0.3))
        XCTAssertNil(seen)
    }

    func testFlushReturnsPostsStillOnScreenPastThreshold() {
        var tracker = SeenDwellTracker(threshold: threshold)
        tracker.didAppear(serverPostId: 1, at: t0)
        tracker.didAppear(serverPostId: 2, at: t0.addingTimeInterval(0.4))
        // At t0+0.6: post 1 has dwelled 0.6 (seen), post 2 only 0.2 (not yet).
        let seen = tracker.flushSeen(at: t0.addingTimeInterval(0.6))
        XCTAssertEqual(seen, [1])
        // Post 1 is not reported twice on a later flush.
        let seenAgain = tracker.flushSeen(at: t0.addingTimeInterval(0.7))
        XCTAssertEqual(seenAgain, [])
    }

    func testDisappearWithoutAppearIsIgnored() {
        var tracker = SeenDwellTracker(threshold: threshold)
        XCTAssertNil(tracker.didDisappear(serverPostId: 99, at: t0))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run (after `make project`): the two `-only-testing` classes (`SpudDataKitTests/PostInteractionSnapshotMappingTests` and `SpudTests/SeenDwellTrackerTests`) with the standard xcodebuild command for `iPhone 17`.
Expected: FAIL — missing `PostInteractionSnapshot(postListRow:)` and `SeenDwellTracker`.

- [ ] **Step 3a: Implement the snapshot mapping**

`SpudDataKit/Services/AppDatabase/PostInteractionSnapshot+PostListRow.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

public extension PostInteractionSnapshot {
    /// Builds a snapshot from a feed row, deriving `instanceHost` from the
    /// community's federation actor id.
    init(postListRow row: PostListRow) {
        let instanceHost = row.communityActorId.flatMap { URL(string: $0)?.host } ?? ""
        self.init(
            titleSnapshot: row.title,
            communityName: row.communityName,
            instanceHost: instanceHost,
            thumbnailUrl: row.thumbnailUrl,
            author: row.creatorName
        )
    }
}
```

- [ ] **Step 3b: Implement the dwell tracker**

`Spud/Scenes/PostList/SeenDwellTracker.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Pure dwell bookkeeping for "seen on screen" capture. The view controller
/// reports appear/disappear events and periodic flushes; the tracker decides
/// which posts have been continuously visible past `threshold`, and reports
/// each post at most once.
struct SeenDwellTracker {
    let threshold: TimeInterval
    private var appearedAt: [Int64: Date] = [:]
    private var alreadySeen: Set<Int64> = []

    init(threshold: TimeInterval) {
        self.threshold = threshold
    }

    mutating func didAppear(serverPostId: Int64, at now: Date) {
        if appearedAt[serverPostId] == nil {
            appearedAt[serverPostId] = now
        }
    }

    /// Records a disappearance. Returns the post id if it dwelled past the
    /// threshold and hasn't been reported yet, else nil.
    mutating func didDisappear(serverPostId: Int64, at now: Date) -> Int64? {
        guard let start = appearedAt.removeValue(forKey: serverPostId) else { return nil }
        guard !alreadySeen.contains(serverPostId) else { return nil }
        if now.timeIntervalSince(start) >= threshold {
            alreadySeen.insert(serverPostId)
            return serverPostId
        }
        return nil
    }

    /// Returns posts currently on screen that have dwelled past the threshold
    /// and haven't been reported yet (marking them reported). Call periodically
    /// while the feed is stationary.
    mutating func flushSeen(at now: Date) -> [Int64] {
        var result: [Int64] = []
        for (postId, start) in appearedAt where !alreadySeen.contains(postId) {
            if now.timeIntervalSince(start) >= threshold {
                alreadySeen.insert(postId)
                result.append(postId)
            }
        }
        return result
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run the Step 2 commands. Expected: PASS (snapshot mapping 2, dwell tracker 4).

- [ ] **Step 5: Commit**

```bash
mint run swiftformat SpudDataKit/Services/AppDatabase/PostInteractionSnapshot+PostListRow.swift Spud/Scenes/PostList/SeenDwellTracker.swift SpudDataKitTests/PostInteractionSnapshotMappingTests.swift SpudTests/SeenDwellTrackerTests.swift
git add SpudDataKit/Services/AppDatabase/PostInteractionSnapshot+PostListRow.swift Spud/Scenes/PostList/SeenDwellTracker.swift SpudDataKitTests/PostInteractionSnapshotMappingTests.swift SpudTests/SeenDwellTrackerTests.swift
git commit -m "feat: add seen-dwell tracker and snapshot mapping"
```

---

## Task 7: Wire seen-capture into `PostListViewController`

**Files:**
- Modify: `Spud/Scenes/PostList/PostListViewController.swift`
- Reference (read): the existing `UITableViewDelegate` conformance, `rowsByServerPostId`, `viewModel.accountKeychainId`, and `appDatabase` accessor in that file.

No isolated unit test (the testable logic is in Task 6). Verification: app build + the full test plan stays green; the dwell tracker/snapshot tests from Task 6 cover the logic.

- [ ] **Step 1: Add the tracker and flush timer**

In `PostListViewController`, add stored properties:
```swift
    private var seenDwellTracker = SeenDwellTracker(threshold: 0.5)
    private var seenFlushTimer: Timer?
```

Start a repeating flush timer in `viewDidAppear` and invalidate it in `viewDidDisappear` (so capture only runs while the feed is visible):
```swift
    // in viewDidAppear(_:)
    seenFlushTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
        guard let self else { return }
        Task { @MainActor in self.flushSeen() }
    }
    // in viewDidDisappear(_:)
    seenFlushTimer?.invalidate()
    seenFlushTimer = nil
    flushSeen() // capture anything still on screen when leaving
```

- [ ] **Step 2: Hook the cell-display lifecycle**

In the `UITableViewDelegate` methods (add them if not present; this VC is the table's delegate), record appear/disappear for post items only:
```swift
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard case let .post(serverPostId) = dataSource.itemIdentifier(for: indexPath) else { return }
        seenDwellTracker.didAppear(serverPostId: serverPostId, at: Date())
    }

    func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        // dataSource.itemIdentifier(for: indexPath) is unreliable here — the
        // snapshot may already have changed — so read the post id stamped on the
        // cell at configure time instead.
        guard let serverPostId = (cell as? PostListPostCell)?.seenTrackingServerPostId else { return }
        if let seen = seenDwellTracker.didDisappear(serverPostId: serverPostId, at: Date()) {
            recordSeen([seen])
        }
    }
```

Because `didEndDisplaying` can't reliably resolve the item id via `indexPath` (the snapshot may have changed), stamp the id on the cell at configure time. In the cell-provider closure where the cell is configured, add:
```swift
    cell.seenTrackingServerPostId = serverPostId
```
and add the stored property to `PostListPostCell` (`Spud/Scenes/PostList/PostListPostCell.swift`):
```swift
    /// Server post id of the row this cell currently shows, used by the feed's
    /// seen-on-screen capture in didEndDisplaying. Not part of rendering.
    var seenTrackingServerPostId: Int64?
```

- [ ] **Step 3: Add the flush + record helpers**

```swift
    private func flushSeen() {
        let seen = seenDwellTracker.flushSeen(at: Date())
        guard !seen.isEmpty else { return }
        recordSeen(seen)
    }

    /// Persists "seen" for the given server post ids, building each snapshot from
    /// the currently-loaded feed row. Fire-and-forget; failures are non-fatal.
    private func recordSeen(_ serverPostIds: [Int64]) {
        let keychainId = viewModel.accountKeychainId
        let snapshots: [(Int64, PostInteractionSnapshot)] = serverPostIds.compactMap { id in
            guard let row = rowsByServerPostId[id] else { return nil }
            return (id, PostInteractionSnapshot(postListRow: row))
        }
        guard !snapshots.isEmpty else { return }
        Task { [appDatabase] in
            for (id, snapshot) in snapshots {
                try? await appDatabase.recordPostSeen(
                    accountKeychainId: keychainId,
                    serverPostId: id,
                    snapshot: snapshot
                )
            }
        }
    }
```

(Confirm the exact names `rowsByServerPostId`, `viewModel.accountKeychainId`, `appDatabase`, and `dataSource` against the file; they are the same ones the existing cell provider and observation use. If `PostListViewController` is not already the table's `UITableViewDelegate`, set `tableView.delegate = self` where the data source is created and add the conformance.)

- [ ] **Step 4: Build + verify**

Run `make project` then `build_and_test.py --scheme Spud --simulator "iPhone 17"`.
Expected: build succeeds; full unit-test plan green (the only pre-existing failure is the known `testPostDetail` UI-test flake). Optional manual: scroll the feed, leave it; query the app-group DB (`sqlite3 ... "SELECT postServerId, seenCount FROM postInteraction WHERE lastSeenAt IS NOT NULL"`) to confirm rows accrue.

- [ ] **Step 5: Commit**

```bash
mint run swiftformat Spud/Scenes/PostList/PostListViewController.swift Spud/Scenes/PostList/PostListPostCell.swift
git add Spud/Scenes/PostList/PostListViewController.swift Spud/Scenes/PostList/PostListPostCell.swift
git commit -m "feat: capture seen-on-screen posts from the feed"
```

---

## Self-review notes (for the implementer)

- **FTS5 availability:** system SQLite on iOS 18 includes FTS5; GRDB's `FTS5()`/`synchronize(withTable:)`/`FTS5Pattern` are the standard API. If `FTS5Pattern(matchingAllTokensIn:)` returns nil for odd input (e.g. only punctuation), the search simply falls back to no FTS join (the observation guards `if hasSearch, let pattern = ...`). When the pattern is nil but the user typed something, the current code treats it as "no filter" — acceptable; if you prefer "no results" on an unparseable query, return `[]` instead.
- **`StatementArguments(arguments)`** is built from a `[DatabaseValueConvertible]`; `FTS5Pattern` and `Int64` both conform. Keep the bind order: FTS pattern (if any) is bound before `accountId` because the FTS `MATCH ?` clause appears before the `WHERE ... accountId = ?` clause in the SQL string.
- **Mode/search restart:** every `viewModel.mode`/`searchText` change must cancel the old `observationTask` before starting a new one, or two streams will fight over the snapshot.
- **`.seen` ordering** depends on GRDB storing `Date` as the lexicographically-sortable text format; the `max(coalesce(...))` expression is correct only under that assumption (the default).

## Done criteria

- FTS5 index exists (v15) and stays in sync via `synchronize(withTable:)`; `AppDatabaseTests` updated and green.
- `observeHistoryRows` returns the correct `PostListRow` set + ordering for Read/Seen/Saved, narrowed by FTS search, all unit-tested.
- A History screen reachable from the account footer reuses the feed cell, switches Read/Seen/Saved, searches, and opens a post on tap.
- The feed records seen-on-screen posts past a ~500ms dwell, batched and fire-and-forget, building snapshots from the loaded feed rows.
- App builds; all new unit tests pass; no regression beyond the pre-existing `testPostDetail` UI-test flake.

## Out of scope / deferred

- New-comment marker UI (separate design-pipeline task), Phase 4 push (dropped for now per the user).
- Tuning dwell threshold / partial-visibility heuristics beyond the 500ms appear/disappear model.
- Server-side history sync (the log is local-only by design).
