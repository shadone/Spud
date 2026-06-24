# Durable, Optimistic Composing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make composing a comment or post instant (shows immediately), durable (drafts + in-flight sends persist across app launches and are never lost), and self-healing (background send queue that retries on bad networks and parks failures for manual retry).

**Architecture:** A single GRDB table `outboundContent` (migration `v18`) stores drafts *and* in-flight/failed sends as one lifecycle (`draft → queued → sending → deleted-on-success | failed`). A per-account actor `ComposerOutboxService` drains the queue, calling `LemmyApi.createComment`/`createPost` through a performer and mirroring the server response — exactly mirroring the shipped `OutboxService` (vote/save/hide) but **keeping** content on permanent failure instead of rolling it back. Comments render optimistically by overlaying outbound rows into the post-detail diffable snapshot; new posts render via a small `PendingPostViewController` that swaps itself for the real post-detail on success. A "Drafts & Outbox" list is the recovery home.

**Tech Stack:** Swift 6 (language mode 6.0 on shipped targets), UIKit, GRDB, LemmyKit (remote SPM pin 0.5.0), Swift Testing (SpudDataKitTests), pointfreeco/swift-snapshot-testing (SpudSnapshots), XcodeGen.

## Global Constraints

- **Swift strict concurrency** `SWIFT_STRICT_CONCURRENCY = complete`; new SpudDataKit/Spud code is Swift 6.0 language mode. Records are `Sendable` structs; services that cross threads are actors or `Sendable`.
- **No emojis** in code, comments, docs, or commit messages. Conventional commit subjects (`feat:`/`fix:`/`refactor:`/`test:`/`docs:`).
- **Branch:** all work on `feat/durable-optimistic-composing` (already created; spec committed at `d58cfd12`). Verify `git branch --show-current` before every commit. Never `git add -A`; stage explicit paths. Never touch `.remember/remember.md` or anything under `/worktrees/`.
- **After adding/removing source files,** run `make project` (XcodeGen) before building, or Xcode won't see them.
- **Build/test:** `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud` for app builds. SpudDataKit unit tests via `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -only-testing:SpudDataKitTests -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -skipMacroValidation test`. Snapshots via `-testPlan SpudSnapshots -destination 'platform=iOS Simulator,name=iPhone 14 Pro'`.
- **GRDB observations** must pass `.async(onQueue: .global(qos: .userInitiated))` (never the default main scheduler — illegal from non-isolated AsyncStream init).
- **Migrations:** append `v18_outboundContent` as the next case in `AppDatabase+Migrations.swift`; never edit a shipped migration.
- **Records** use `Codable, FetchableRecord, MutablePersistableRecord, Sendable, Equatable` with property-based column inference and a `didInsert` hook (mirror `PendingOperationRecord`).
- **Reachability/classification reuse:** reuse the existing public `OutboxFailureClass.classify(_:isOnline:)` and `ReachabilityMonitoring`. Do **not** modify `OutboxService` / `pendingOperation` (the vote/save/hide outbox must not regress).

---

## File Structure

**New — SpudDataKit:**
- `Services/AppDatabase/Records/OutboundContentRecord.swift` — the record + `OutboundKind`/`OutboundStatus` enums + `draftKey` helpers + `OutboundDraftInput`.
- `Services/AppDatabase/OutboundContentWrites.swift` — `AppDatabase` extension: upsert draft, transitions, due/all queries, dedup pre-check, delete.
- `Services/AppDatabase/OutboundContentObservations.swift` — `observeOutboundComments` + `observeOutboundContent` AsyncStreams.
- `Services/Outbox/ComposerOutboxService.swift` — the actor + `ComposerOutboxServiceType`, `ComposerOutboxFailure`, `ComposerOutboxSuccess`, `composerBackoffDelay`.
- `Services/Outbox/OutboundContentPerforming.swift` — performer protocol + `LemmyComposerPerformer`.

**Modified — SpudDataKit:**
- `Services/AppDatabase/AppDatabase+Migrations.swift` — add `v18_outboundContent`.
- `Services/Lemmy/LemmyService.swift` — lazy `composerOutboxService()`; high-level `saveDraft`/`submitDraft`/`retryComposition`/`discardComposition`/`loadDraft` + `composerFailureEvents`/`composerSuccessEvents`.
- `Services/Lemmy/LemmyServiceType.swift` (protocol) — declare the new methods.
- `Services/Account/AccountScope.swift` — forward `composerFailureEvents`/`composerSuccessEvents`.

**New — Spud (app):**
- `Scenes/Composer/PendingPostViewController.swift` — optimistic post screen + swap-on-success.
- `Scenes/DraftsOutbox/OutboundContentListViewController.swift` + `OutboundContentListViewModel.swift` — recovery home.
- `Scenes/PostDetail/Content/Comment/PendingCommentCellState.swift` — small value type for the pending cell branch.

**Modified — Spud (app):**
- `Scenes/Composer/ComposerViewModel.swift` / `ComposerViewController.swift` — draft load/save, submit→enqueue, Mail-style dismiss, no blocking spinner.
- `Scenes/Composer/NewPostViewModel.swift` / `NewPostViewController.swift` — same for posts; success pushes pending post detail.
- `Scenes/PostDetail/Content/PostDetailViewController.swift` — outbound-comment overlay + pending cell branch + tap actions.
- `Scenes/PostDetail/Content/Comment/PostDetailCommentCell.swift` — `configurePending(...)`.
- `Scenes/MainWindow/MainWindow.swift` — push pending post detail, swap-on-success, consume composer failure/success events, "Drafts & Outbox" entry + toast "View".

---

## PHASE 1 — Durable store + send engine (headless)

Delivers a working, fully-tested data layer and queue. No UI behavior change yet (the composer can route through it invisibly at the end of the phase, still dismissing on success).

### Task 1: `OutboundContentRecord` + enums + draftKey

**Files:**
- Create: `SpudDataKit/Services/AppDatabase/Records/OutboundContentRecord.swift`
- Test: `SpudDataKitTests/OutboundContentRecordTests.swift`

**Interfaces:**
- Produces:
  - `public enum OutboundKind: Int64, Codable, Sendable { case comment = 0; case post = 1 }`
  - `public enum OutboundStatus: Int64, Codable, Sendable { case draft = 0; case queued = 1; case sending = 2; case failed = 3 }`
  - `public struct OutboundContentRecord` (fields below) with `static let databaseTableName = "outboundContent"`.
  - `public struct OutboundDraftInput: Sendable` (kind, body, postServerId?, parentCommentServerId?, communityServerId?, title?, url?, nsfw, postType: Int64).
  - `OutboundContentRecord.commentDraftKey(postServerId:parentCommentServerId:) -> String`
  - `OutboundContentRecord.postDraftKey(communityServerId:) -> String`
  - `OutboundContentRecord.draftKey(for input: OutboundDraftInput) -> String`

- [ ] **Step 1: Write the failing test**

```swift
// SpudDataKitTests/OutboundContentRecordTests.swift
import Testing
@testable import SpudDataKit

struct OutboundContentRecordTests {
    @Test func commentDraftKey_topLevel_usesZeroForParent() {
        #expect(OutboundContentRecord.commentDraftKey(postServerId: 42, parentCommentServerId: nil) == "c:42:0")
    }

    @Test func commentDraftKey_reply_includesParent() {
        #expect(OutboundContentRecord.commentDraftKey(postServerId: 42, parentCommentServerId: 99) == "c:42:99")
    }

    @Test func postDraftKey_noCommunity_usesZero() {
        #expect(OutboundContentRecord.postDraftKey(communityServerId: nil) == "p:0")
    }

    @Test func draftKey_dispatchesOnKind() {
        let comment = OutboundDraftInput(kind: .comment, body: "hi", postServerId: 7, parentCommentServerId: nil,
                                         communityServerId: nil, title: nil, url: nil, nsfw: false, postType: 0)
        let post = OutboundDraftInput(kind: .post, body: "", postServerId: nil, parentCommentServerId: nil,
                                      communityServerId: 3, title: "T", url: nil, nsfw: false, postType: 0)
        #expect(OutboundContentRecord.draftKey(for: comment) == "c:7:0")
        #expect(OutboundContentRecord.draftKey(for: post) == "p:3")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -only-testing:SpudDataKitTests/OutboundContentRecordTests -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -skipMacroValidation test`
Expected: FAIL — `OutboundContentRecord` not found (after `make project`, which you must run first since the test file is new).

- [ ] **Step 3: Write the record**

```swift
// SpudDataKit/Services/AppDatabase/Records/OutboundContentRecord.swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

/// Which kind of content a row will create.
public enum OutboundKind: Int64, Codable, Sendable {
    case comment = 0
    case post = 1
}

/// Lifecycle of an outbound row. There is no `sent` — a successful send deletes
/// the row (the real content lives in `comment`/`post`).
public enum OutboundStatus: Int64, Codable, Sendable {
    case draft = 0
    case queued = 1
    case sending = 2
    case failed = 3
}

/// The mutable inputs a composer collects, independent of send bookkeeping.
public struct OutboundDraftInput: Sendable, Equatable {
    public var kind: OutboundKind
    public var body: String
    public var postServerId: Int64?
    public var parentCommentServerId: Int64?
    public var communityServerId: Int64?
    public var title: String?
    public var url: String?
    public var nsfw: Bool
    public var postType: Int64

    public init(
        kind: OutboundKind, body: String, postServerId: Int64?, parentCommentServerId: Int64?,
        communityServerId: Int64?, title: String?, url: String?, nsfw: Bool, postType: Int64
    ) {
        self.kind = kind; self.body = body; self.postServerId = postServerId
        self.parentCommentServerId = parentCommentServerId; self.communityServerId = communityServerId
        self.title = title; self.url = url; self.nsfw = nsfw; self.postType = postType
    }
}

/// A persisted draft / in-flight / failed composition (comment or post).
public struct OutboundContentRecord: Codable, FetchableRecord, MutablePersistableRecord, Sendable, Equatable {
    public var id: Int64?
    public var clientToken: String
    public var accountId: Int64
    public var kind: Int64
    public var status: Int64
    public var draftKey: String
    public var body: String
    public var postServerId: Int64?
    public var parentCommentServerId: Int64?
    public var communityServerId: Int64?
    public var title: String?
    public var url: String?
    public var nsfw: Bool
    public var postType: Int64
    public var attempts: Int64
    public var lastError: String?
    public var nextAttemptAt: Double?
    public var createdAt: Double
    public var updatedAt: Double

    public static let databaseTableName = "outboundContent"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public static func commentDraftKey(postServerId: Int64, parentCommentServerId: Int64?) -> String {
        "c:\(postServerId):\(parentCommentServerId.map(String.init) ?? "0")"
    }

    public static func postDraftKey(communityServerId: Int64?) -> String {
        "p:\(communityServerId.map(String.init) ?? "0")"
    }

    public static func draftKey(for input: OutboundDraftInput) -> String {
        switch input.kind {
        case .comment:
            commentDraftKey(postServerId: input.postServerId ?? 0, parentCommentServerId: input.parentCommentServerId)
        case .post:
            postDraftKey(communityServerId: input.communityServerId)
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run the Step 2 command. Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud && git branch --show-current   # must print feat/durable-optimistic-composing
make project
git add SpudDataKit/Services/AppDatabase/Records/OutboundContentRecord.swift SpudDataKitTests/OutboundContentRecordTests.swift
git commit -m "feat: add OutboundContentRecord for durable composing"
```

---

### Task 2: `v18_outboundContent` migration

**Files:**
- Modify: `SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift` (append after the `v17_pendingOperation` block, before `return migrator`)
- Test: `SpudDataKitTests/OutboundContentMigrationTests.swift`

**Interfaces:**
- Consumes: `OutboundContentRecord` (Task 1), `AppDatabase.inMemory()`, `appDatabase.writer`.
- Produces: table `outboundContent` with a partial unique index `outboundContent_draft_unique` on `(accountId, draftKey) WHERE status = 0`.

- [ ] **Step 1: Write the failing test**

```swift
// SpudDataKitTests/OutboundContentMigrationTests.swift
import GRDB
import Testing
@testable import SpudDataKit

struct OutboundContentMigrationTests {
    @Test func tableExistsAfterMigration() async throws {
        let db = try AppDatabase.inMemory()
        let exists = try await db.writer.read { try $0.tableExists("outboundContent") }
        #expect(exists)
    }

    @Test func partialUniqueIndexAllowsManyNonDrafts_butOneDraftPerTarget() async throws {
        let db = try AppDatabase.inMemory()
        // Seed an account row (FK target). Minimal insert via raw SQL is brittle across schema;
        // instead use accountId that satisfies the FK by inserting through the account table.
        let accountId = try await Self.seedAccount(db)
        try await db.writer.write { write in
            func row(status: Int64, token: String) -> OutboundContentRecord {
                OutboundContentRecord(
                    id: nil, clientToken: token, accountId: accountId, kind: 0, status: status,
                    draftKey: "c:1:0", body: "x", postServerId: 1, parentCommentServerId: nil,
                    communityServerId: nil, title: nil, url: nil, nsfw: false, postType: 0,
                    attempts: 0, lastError: nil, nextAttemptAt: nil, createdAt: 0, updatedAt: 0
                )
            }
            var d1 = row(status: 0, token: "a"); try d1.insert(write)
            // Two queued (status=1) rows to the same target are allowed.
            var q1 = row(status: 1, token: "b"); try q1.insert(write)
            var q2 = row(status: 1, token: "c"); try q2.insert(write)
        }
        // A second draft (status=0) to the same target must violate the partial unique index.
        await #expect(throws: (any Error).self) {
            try await db.writer.write { write in
                var d2 = OutboundContentRecord(
                    id: nil, clientToken: "d", accountId: accountId, kind: 0, status: 0,
                    draftKey: "c:1:0", body: "y", postServerId: 1, parentCommentServerId: nil,
                    communityServerId: nil, title: nil, url: nil, nsfw: false, postType: 0,
                    attempts: 0, lastError: nil, nextAttemptAt: nil, createdAt: 0, updatedAt: 0
                )
                try d2.insert(write)
            }
        }
    }

    /// Inserts a minimal account row and returns its id. Mirrors how other
    /// SpudDataKitTests seed FK parents (see AccountRecord usage in existing tests).
    static func seedAccount(_ db: AppDatabase) async throws -> Int64 {
        try await db.writer.write { write in
            try write.execute(sql: """
                INSERT INTO account (accountKeychainId, siteId, isDefaultAccount, isSignedOutAccount, sortOrder)
                VALUES ('test@example.com',
                        (SELECT id FROM site LIMIT 1),
                        1, 1, 0)
            """)
            return write.lastInsertedRowID
        }
    }
}
```

> NOTE for implementer: the `account` insert columns above are illustrative. Before writing this test, open `SpudDataKit/Services/AppDatabase/Records/AccountRecord.swift` and the `v1` migration's `account`/`site` table definitions and adjust the `INSERT` to the real required columns (NOT NULL columns without defaults). If seeding `site` is also required, insert a minimal `site` first. Keep the assertions unchanged.

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild ... -only-testing:SpudDataKitTests/OutboundContentMigrationTests ... test`
Expected: FAIL — `tableExists("outboundContent")` is false.

- [ ] **Step 3: Add the migration**

In `AppDatabase+Migrations.swift`, immediately after the `v17_pendingOperation` registration block:

```swift
        migrator.registerMigration("v18_outboundContent") { db in
            try db.create(table: "outboundContent") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("clientToken", .text).notNull().unique()
                t.column("accountId", .integer)
                    .notNull()
                    .indexed()
                    .references("account", onDelete: .cascade)
                t.column("kind", .integer).notNull()
                t.column("status", .integer).notNull()
                t.column("draftKey", .text).notNull()
                t.column("body", .text).notNull().defaults(to: "")
                t.column("postServerId", .integer)
                t.column("parentCommentServerId", .integer)
                t.column("communityServerId", .integer)
                t.column("title", .text)
                t.column("url", .text)
                t.column("nsfw", .boolean).notNull().defaults(to: false)
                t.column("postType", .integer).notNull().defaults(to: 0)
                t.column("attempts", .integer).notNull().defaults(to: 0)
                t.column("lastError", .text)
                t.column("nextAttemptAt", .double)
                t.column("createdAt", .double).notNull()
                t.column("updatedAt", .double).notNull()
            }
            // One *draft* per target; in-flight/failed rows are unconstrained.
            try db.create(
                index: "outboundContent_draft_unique",
                on: "outboundContent",
                columns: ["accountId", "draftKey"],
                options: [.unique],
                condition: Column("status") == 0
            )
        }
```

- [ ] **Step 4: Run test to verify it passes**

Run the Step 2 command. Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift SpudDataKitTests/OutboundContentMigrationTests.swift
git commit -m "feat: add v18 outboundContent migration"
```

---

### Task 3: `OutboundContentWrites` — draft upsert + lifecycle transitions

**Files:**
- Create: `SpudDataKit/Services/AppDatabase/OutboundContentWrites.swift`
- Test: `SpudDataKitTests/OutboundContentWritesTests.swift`

**Interfaces:**
- Consumes: `OutboundContentRecord`, `OutboundDraftInput`, `OutboundStatus` (Task 1); migration (Task 2); `AppDatabase.inMemory()`, `seedAccount` helper (copy into this test file or factor a shared test helper).
- Produces (all on `public extension AppDatabase`, `async throws`):
  - `upsertOutboundDraft(_ input: OutboundDraftInput, accountId: Int64, now: Double) async throws -> String` (returns clientToken)
  - `loadOutboundDraft(accountId: Int64, draftKey: String) async throws -> OutboundContentRecord?`
  - `markOutboundQueued(clientToken: String, now: Double) async throws`
  - `markOutboundSending(id: Int64, now: Double) async throws`
  - `markOutboundRetrying(id: Int64, lastError: String, nextAttemptAt: Double, now: Double) async throws`
  - `markOutboundFailed(id: Int64, lastError: String, now: Double) async throws`
  - `deleteOutbound(clientToken: String) async throws`
  - `dueOutbound(accountId: Int64, asOf now: Double) async throws -> [OutboundContentRecord]`
  - `allOutbound(accountId: Int64) async throws -> [OutboundContentRecord]`

- [ ] **Step 1: Write the failing tests**

```swift
// SpudDataKitTests/OutboundContentWritesTests.swift
import Testing
@testable import SpudDataKit

struct OutboundContentWritesTests {
    func makeInput() -> OutboundDraftInput {
        OutboundDraftInput(kind: .comment, body: "hi", postServerId: 1, parentCommentServerId: nil,
                           communityServerId: nil, title: nil, url: nil, nsfw: false, postType: 0)
    }

    @Test func upsertDraft_insertsThenUpdatesSameRow() async throws {
        let db = try AppDatabase.inMemory()
        let acc = try await OutboundContentMigrationTests.seedAccount(db)
        let token1 = try await db.upsertOutboundDraft(makeInput(), accountId: acc, now: 100)
        var updated = makeInput(); updated.body = "edited"
        let token2 = try await db.upsertOutboundDraft(updated, accountId: acc, now: 200)
        #expect(token1 == token2) // same draft row reused per draftKey
        let loaded = try await db.loadOutboundDraft(accountId: acc, draftKey: "c:1:0")
        #expect(loaded?.body == "edited")
        #expect(loaded?.updatedAt == 200)
    }

    @Test func submitTransitionsDraftToQueued_thenDueIncludesIt() async throws {
        let db = try AppDatabase.inMemory()
        let acc = try await OutboundContentMigrationTests.seedAccount(db)
        let token = try await db.upsertOutboundDraft(makeInput(), accountId: acc, now: 0)
        try await db.markOutboundQueued(clientToken: token, now: 50)
        let due = try await db.dueOutbound(accountId: acc, asOf: 50)
        #expect(due.count == 1)
        #expect(due.first?.status == OutboundStatus.queued.rawValue)
        #expect(due.first?.nextAttemptAt == 50)
    }

    @Test func retrying_setsBackoff_notDueUntilTime() async throws {
        let db = try AppDatabase.inMemory()
        let acc = try await OutboundContentMigrationTests.seedAccount(db)
        let token = try await db.upsertOutboundDraft(makeInput(), accountId: acc, now: 0)
        try await db.markOutboundQueued(clientToken: token, now: 0)
        let id = try await db.dueOutbound(accountId: acc, asOf: 0).first!.id!
        try await db.markOutboundRetrying(id: id, lastError: "net", nextAttemptAt: 100, now: 10)
        #expect(try await db.dueOutbound(accountId: acc, asOf: 50).isEmpty)        // backoff not elapsed
        #expect(try await db.dueOutbound(accountId: acc, asOf: 100).count == 1)    // now due
    }

    @Test func failed_isNotAutoDrained_butShowsInAll() async throws {
        let db = try AppDatabase.inMemory()
        let acc = try await OutboundContentMigrationTests.seedAccount(db)
        let token = try await db.upsertOutboundDraft(makeInput(), accountId: acc, now: 0)
        try await db.markOutboundQueued(clientToken: token, now: 0)
        let id = try await db.dueOutbound(accountId: acc, asOf: 0).first!.id!
        try await db.markOutboundFailed(id: id, lastError: "403", now: 10)
        #expect(try await db.dueOutbound(accountId: acc, asOf: .greatestFiniteMagnitude).isEmpty)
        #expect(try await db.allOutbound(accountId: acc).count == 1)
    }

    @Test func delete_removesRow() async throws {
        let db = try AppDatabase.inMemory()
        let acc = try await OutboundContentMigrationTests.seedAccount(db)
        let token = try await db.upsertOutboundDraft(makeInput(), accountId: acc, now: 0)
        try await db.deleteOutbound(clientToken: token)
        #expect(try await db.allOutbound(accountId: acc).isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild ... -only-testing:SpudDataKitTests/OutboundContentWritesTests ... test` (run `make project` first). Expected: FAIL — methods undefined.

- [ ] **Step 3: Implement the writes**

```swift
// SpudDataKit/Services/AppDatabase/OutboundContentWrites.swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

public extension AppDatabase {
    /// Upsert the single draft row for `input`'s target. Returns its clientToken.
    func upsertOutboundDraft(_ input: OutboundDraftInput, accountId: Int64, now: Double) async throws -> String {
        try await writer.write { db in
            let key = OutboundContentRecord.draftKey(for: input)
            if var existing = try OutboundContentRecord
                .filter(Column("accountId") == accountId)
                .filter(Column("draftKey") == key)
                .filter(Column("status") == OutboundStatus.draft.rawValue)
                .fetchOne(db)
            {
                existing.body = input.body
                existing.title = input.title
                existing.url = input.url
                existing.nsfw = input.nsfw
                existing.postType = input.postType
                existing.postServerId = input.postServerId
                existing.parentCommentServerId = input.parentCommentServerId
                existing.communityServerId = input.communityServerId
                existing.updatedAt = now
                try existing.update(db)
                return existing.clientToken
            } else {
                let token = UUID().uuidString
                var row = OutboundContentRecord(
                    id: nil, clientToken: token, accountId: accountId, kind: input.kind.rawValue,
                    status: OutboundStatus.draft.rawValue, draftKey: key, body: input.body,
                    postServerId: input.postServerId, parentCommentServerId: input.parentCommentServerId,
                    communityServerId: input.communityServerId, title: input.title, url: input.url,
                    nsfw: input.nsfw, postType: input.postType, attempts: 0, lastError: nil,
                    nextAttemptAt: nil, createdAt: now, updatedAt: now
                )
                try row.insert(db)
                return token
            }
        }
    }

    func loadOutboundDraft(accountId: Int64, draftKey: String) async throws -> OutboundContentRecord? {
        try await writer.read { db in
            try OutboundContentRecord
                .filter(Column("accountId") == accountId)
                .filter(Column("draftKey") == draftKey)
                .filter(Column("status") == OutboundStatus.draft.rawValue)
                .fetchOne(db)
        }
    }

    func markOutboundQueued(clientToken: String, now: Double) async throws {
        try await writer.write { db in
            try db.execute(sql: """
                UPDATE outboundContent
                SET status = ?, nextAttemptAt = ?, lastError = NULL, updatedAt = ?
                WHERE clientToken = ?
                """, arguments: [OutboundStatus.queued.rawValue, now, now, clientToken])
        }
    }

    func markOutboundSending(id: Int64, now: Double) async throws {
        try await writer.write { db in
            try db.execute(sql: "UPDATE outboundContent SET status = ?, updatedAt = ? WHERE id = ?",
                           arguments: [OutboundStatus.sending.rawValue, now, id])
        }
    }

    func markOutboundRetrying(id: Int64, lastError: String, nextAttemptAt: Double, now: Double) async throws {
        try await writer.write { db in
            try db.execute(sql: """
                UPDATE outboundContent
                SET status = ?, attempts = attempts + 1, lastError = ?, nextAttemptAt = ?, updatedAt = ?
                WHERE id = ?
                """, arguments: [OutboundStatus.queued.rawValue, lastError, nextAttemptAt, now, id])
        }
    }

    func markOutboundFailed(id: Int64, lastError: String, now: Double) async throws {
        try await writer.write { db in
            try db.execute(sql: """
                UPDATE outboundContent
                SET status = ?, attempts = attempts + 1, lastError = ?, nextAttemptAt = NULL, updatedAt = ?
                WHERE id = ?
                """, arguments: [OutboundStatus.failed.rawValue, lastError, now, id])
        }
    }

    func deleteOutbound(clientToken: String) async throws {
        try await writer.write { db in
            _ = try OutboundContentRecord.filter(Column("clientToken") == clientToken).deleteAll(db)
        }
    }

    /// Rows eligible for an automatic send pass: queued/sending whose backoff has
    /// elapsed. `failed` rows are excluded (they wait for an explicit retry).
    func dueOutbound(accountId: Int64, asOf now: Double) async throws -> [OutboundContentRecord] {
        try await writer.read { db in
            try OutboundContentRecord
                .filter(Column("accountId") == accountId)
                .filter([OutboundStatus.queued.rawValue, OutboundStatus.sending.rawValue].contains(Column("status")))
                .filter(Column("nextAttemptAt") == nil || Column("nextAttemptAt") <= now)
                .order(Column("createdAt").asc)
                .fetchAll(db)
        }
    }

    func allOutbound(accountId: Int64) async throws -> [OutboundContentRecord] {
        try await writer.read { db in
            try OutboundContentRecord
                .filter(Column("accountId") == accountId)
                .order(Column("createdAt").asc)
                .fetchAll(db)
        }
    }
}
```

- [ ] **Step 4: Run to verify passing**

Run the Step 2 command. Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add SpudDataKit/Services/AppDatabase/OutboundContentWrites.swift SpudDataKitTests/OutboundContentWritesTests.swift
git commit -m "feat: add OutboundContent write helpers and lifecycle transitions"
```

---

### Task 4: Dedup pre-check — `matchingServerCommentExists`

**Files:**
- Modify: `SpudDataKit/Services/AppDatabase/OutboundContentWrites.swift` (append a method)
- Test: `SpudDataKitTests/OutboundContentDedupTests.swift`

**Interfaces:**
- Produces: `func matchingServerCommentExists(accountId: Int64, postServerId: Int64?, parentCommentServerId: Int64?, body: String) async throws -> Bool` on `public extension AppDatabase`. Returns true when a `comment` row authored by this account already exists under the same post+parent with the same trimmed body (the "response lost after the server committed" case).

- [ ] **Step 1: Write the failing test**

```swift
// SpudDataKitTests/OutboundContentDedupTests.swift
import Testing
@testable import SpudDataKit

struct OutboundContentDedupTests {
    @Test func noMatchWhenNoComment() async throws {
        let db = try AppDatabase.inMemory()
        let acc = try await OutboundContentMigrationTests.seedAccount(db)
        let exists = try await db.matchingServerCommentExists(
            accountId: acc, postServerId: 1, parentCommentServerId: nil, body: "hello")
        #expect(exists == false)
    }
    // A positive-match test requires seeding a full post+comment authored by the
    // account; cover that in CommentImporter-backed integration once available.
    // This unit test pins the negative (most common) path and the query shape.
}
```

> NOTE for implementer: a full positive-match test needs a seeded `post` + `comment` whose creator maps to the account's person. Seeding that by hand is heavy; rely on the existing `CommentImporter` test fixtures if one is convenient, otherwise keep the negative-path unit test here and add a positive integration test in Task 6's engine tests using the fake performer + a real `upsertComment`.

- [ ] **Step 2: Run to verify failure** — method undefined. (`make project` first.)

- [ ] **Step 3: Implement**

Append to `OutboundContentWrites.swift`:

```swift
public extension AppDatabase {
    /// True if a comment authored by `accountId`'s person already exists under the
    /// same post + parent with the same trimmed body. Used to avoid double-sending
    /// when a prior attempt committed server-side but the response was lost.
    func matchingServerCommentExists(
        accountId: Int64, postServerId: Int64?, parentCommentServerId: Int64?, body: String
    ) async throws -> Bool {
        guard let postServerId else { return false }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return try await writer.read { db in
            // The current account's person id (the comment's creator must match).
            let personId = try Int64.fetchOne(db, sql: """
                SELECT person.id FROM account
                JOIN person ON person.personId = account.personId AND person.siteId = account.siteId
                WHERE account.id = ?
                """, arguments: [accountId])
            // account.personId may be null for signed-out; then no match possible.
            guard let personId else { return false }
            let sql: String
            let args: StatementArguments
            if let parentCommentServerId {
                sql = """
                    SELECT 1 FROM comment
                    JOIN post ON post.id = comment.postId
                    WHERE post.postId = ? AND comment.creatorId = ?
                      AND TRIM(comment.body) = ? AND comment.parentCommentServerId = ?
                    LIMIT 1
                    """
                args = [postServerId, personId, trimmed, parentCommentServerId]
            } else {
                sql = """
                    SELECT 1 FROM comment
                    JOIN post ON post.id = comment.postId
                    WHERE post.postId = ? AND comment.creatorId = ?
                      AND TRIM(comment.body) = ? AND comment.parentCommentServerId IS NULL
                    LIMIT 1
                    """
                args = [postServerId, personId, trimmed]
            }
            return try Bool.fetchOne(db, sql: sql, arguments: args) ?? false
        }
    }
}
```

> NOTE for implementer: verify the real column names before running — open `SpudDataKit/Services/AppDatabase/Records/Comment.swift` and confirm (a) the comment table has a parent linkage column (the explorer saw path/parent linkage; the column may be named differently than `parentCommentServerId` — adjust the SQL to the actual column, e.g. a `path`/`parentId`), and (b) how `account.personId`/`account.siteId` relate to `person`. If the account→person mapping differs, adjust the personId subquery. Keep the method signature and the negative-path test unchanged.

- [ ] **Step 4: Run to verify passing.** Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add SpudDataKit/Services/AppDatabase/OutboundContentWrites.swift SpudDataKitTests/OutboundContentDedupTests.swift
git commit -m "feat: add server-comment dedup pre-check for outbound sends"
```

---

### Task 5: Performer — `OutboundContentPerforming` + `LemmyComposerPerformer`

**Files:**
- Create: `SpudDataKit/Services/Outbox/OutboundContentPerforming.swift`
- Test: `SpudDataKitTests/LemmyComposerPerformerTests.swift` (optional light test — the real coverage is the engine test in Task 6 with a fake performer; this task is mostly the protocol + concrete type)

**Interfaces:**
- Consumes: `OutboundContentRecord`, `OutboundKind`; `LemmyApi` (`createComment(postID:content:parentID:)`, `createPost(communityID:name:url:body:nsfw:)`); `AppDatabase.upsertComment(from:accountId:siteId:respectsPendingOutbox:)`, `AppDatabase.upsertPost(from:accountId:siteId:respectsPendingOutbox:)`.
- Produces:
  - `public protocol OutboundContentPerforming: Sendable { func perform(_ record: OutboundContentRecord) async throws -> Int64? }`
  - `public struct LemmyComposerPerformer: OutboundContentPerforming` (holds `api`, `appDatabase`, `accountId`, `siteId`); returns the new server post id for posts, `nil` for comments.

- [ ] **Step 1: Write the file** (this is a thin adapter mirroring `LemmyOutboxPerformer`; no standalone failing test — covered by Task 6)

```swift
// SpudDataKit/Services/Outbox/OutboundContentPerforming.swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

/// Sends an outbound row to the server. Returns the new post's server id for
/// posts (so the pending post screen can swap to the real one); nil for comments.
public protocol OutboundContentPerforming: Sendable {
    func perform(_ record: OutboundContentRecord) async throws -> Int64?
}

public struct LemmyComposerPerformer: OutboundContentPerforming {
    let api: LemmyApi
    let appDatabase: AppDatabase
    let accountId: Int64
    let siteId: Int64

    public init(api: LemmyApi, appDatabase: AppDatabase, accountId: Int64, siteId: Int64) {
        self.api = api
        self.appDatabase = appDatabase
        self.accountId = accountId
        self.siteId = siteId
    }

    public func perform(_ record: OutboundContentRecord) async throws -> Int64? {
        guard let kind = OutboundKind(rawValue: record.kind) else { return nil }
        switch kind {
        case .comment:
            guard let postServerId = record.postServerId else { return nil }
            let response = try await api.createComment(
                postID: Components.Schemas.PostID(postServerId),
                content: record.body,
                parentID: record.parentCommentServerId.map { Components.Schemas.CommentID($0) }
            )
            try await appDatabase.upsertComment(
                from: response.comment_view, accountId: accountId, siteId: siteId, respectsPendingOutbox: false
            )
            return nil
        case .post:
            guard let communityServerId = record.communityServerId else { return nil }
            let trimmedBody = record.body.trimmingCharacters(in: .whitespacesAndNewlines)
            let response = try await api.createPost(
                communityID: Components.Schemas.CommunityID(communityServerId),
                name: record.title ?? "",
                url: record.url,
                body: trimmedBody.isEmpty ? nil : trimmedBody,
                nsfw: record.nsfw
            )
            try await appDatabase.upsertPost(
                from: response.post_view, accountId: accountId, siteId: siteId, respectsPendingOutbox: false
            )
            return Int64(response.post_view.post.id)
        }
    }
}
```

> NOTE for implementer: confirm `api.createPost` parameter labels against `LemmyService.createPost` (it calls `api.createPost(communityID:name:url:body:nsfw:)`) and that `upsertComment(from:accountId:siteId:respectsPendingOutbox:)` / `upsertPost(...)` exist with those labels (they are used verbatim by `LemmyOutboxPerformer`). Adjust only if labels differ.

- [ ] **Step 2: Build to verify it compiles**

Run: `make project && python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add SpudDataKit/Services/Outbox/OutboundContentPerforming.swift
git commit -m "feat: add LemmyComposerPerformer for outbound sends"
```

---

### Task 6: `ComposerOutboxService` actor (drain, retry, backoff, events)

**Files:**
- Create: `SpudDataKit/Services/Outbox/ComposerOutboxService.swift`
- Test: `SpudDataKitTests/ComposerOutboxServiceTests.swift`

**Interfaces:**
- Consumes: writes (Tasks 3–4), `OutboundContentPerforming` (Task 5), `ReachabilityMonitoring`, `OutboxFailureClass.classify(_:isOnline:)`.
- Produces:
  - `public struct ComposerOutboxFailure: Sendable, Equatable { public let clientToken: String; public let kind: OutboundKind }`
  - `public struct ComposerOutboxSuccess: Sendable, Equatable { public let clientToken: String; public let kind: OutboundKind; public let serverPostId: Int64? }`
  - `public protocol ComposerOutboxServiceType: Actor { func submit(clientToken: String) async; func retry(clientToken: String) async; func discard(clientToken: String) async; func drainOnce() async; func drainAll() async; func start() async; var failureEvents: AsyncStream<ComposerOutboxFailure> { get }; var successEvents: AsyncStream<ComposerOutboxSuccess> { get } }`
  - `public actor ComposerOutboxService: ComposerOutboxServiceType`
  - constant `static let maxAutoAttempts: Int64 = 8`
  - `static func composerBackoffDelay(attempts: Int64) -> Double` (`min(2 * 2^(attempts-1), 300)`)

- [ ] **Step 1: Write the failing tests** (fake performer drives transient/permanent/success/dedup)

```swift
// SpudDataKitTests/ComposerOutboxServiceTests.swift
import Testing
@testable import SpudDataKit

private actor FakePerformer: OutboundContentPerforming {
    enum Mode { case success(Int64?), throwTransient, throwPermanent }
    var mode: Mode
    private(set) var calls = 0
    init(_ mode: Mode) { self.mode = mode }
    func set(_ m: Mode) { mode = m }
    func perform(_ record: OutboundContentRecord) async throws -> Int64? {
        calls += 1
        switch mode {
        case let .success(id): return id
        case .throwTransient: throw URLError(.notConnectedToInternet)
        case .throwPermanent: throw LemmyServiceError.requiresAuthentication
        }
    }
}

private final class FakeReachability: ReachabilityMonitoring, @unchecked Sendable {
    @MainActor var isOnline: Bool = true
    @MainActor var statusStream: AsyncStream<Bool> { AsyncStream { $0.finish() } }
}

struct ComposerOutboxServiceTests {
    func makeInput() -> OutboundDraftInput {
        OutboundDraftInput(kind: .comment, body: "hi", postServerId: 1, parentCommentServerId: nil,
                           communityServerId: nil, title: nil, url: nil, nsfw: false, postType: 0)
    }

    @Test func successDeletesRowAndEmitsSuccess() async throws {
        let db = try AppDatabase.inMemory()
        let acc = try await OutboundContentMigrationTests.seedAccount(db)
        let performer = FakePerformer(.success(nil))
        let svc = ComposerOutboxService(accountId: acc, appDatabase: db, performer: performer,
                                        reachability: FakeReachability(), now: { 0 })
        let successes = await svc.successEvents
        let token = try await db.upsertOutboundDraft(makeInput(), accountId: acc, now: 0)
        await svc.submit(clientToken: token)
        #expect(try await db.allOutbound(accountId: acc).isEmpty)
        var it = successes.makeAsyncIterator()
        let event = await it.next()
        #expect(event?.clientToken == token)
    }

    @Test func transientFailureRequeuesWithBackoff() async throws {
        let db = try AppDatabase.inMemory()
        let acc = try await OutboundContentMigrationTests.seedAccount(db)
        let performer = FakePerformer(.throwTransient)
        let svc = ComposerOutboxService(accountId: acc, appDatabase: db, performer: performer,
                                        reachability: FakeReachability(), now: { 0 })
        let token = try await db.upsertOutboundDraft(makeInput(), accountId: acc, now: 0)
        await svc.submit(clientToken: token)
        let rows = try await db.allOutbound(accountId: acc)
        #expect(rows.count == 1)
        #expect(rows.first?.status == OutboundStatus.queued.rawValue) // still retryable
        #expect((rows.first?.nextAttemptAt ?? 0) > 0)                 // backoff scheduled
        #expect(rows.first?.attempts == 1)
    }

    @Test func permanentFailureParksAsFailedAndEmitsFailure() async throws {
        let db = try AppDatabase.inMemory()
        let acc = try await OutboundContentMigrationTests.seedAccount(db)
        let performer = FakePerformer(.throwPermanent)
        let svc = ComposerOutboxService(accountId: acc, appDatabase: db, performer: performer,
                                        reachability: FakeReachability(), now: { 0 })
        let failures = await svc.failureEvents
        let token = try await db.upsertOutboundDraft(makeInput(), accountId: acc, now: 0)
        await svc.submit(clientToken: token)
        let rows = try await db.allOutbound(accountId: acc)
        #expect(rows.first?.status == OutboundStatus.failed.rawValue) // kept, not deleted
        var it = failures.makeAsyncIterator()
        #expect(await it.next()?.clientToken == token)
    }

    @Test func retryFlipsFailedBackToQueuedAndSends() async throws {
        let db = try AppDatabase.inMemory()
        let acc = try await OutboundContentMigrationTests.seedAccount(db)
        let performer = FakePerformer(.throwPermanent)
        let svc = ComposerOutboxService(accountId: acc, appDatabase: db, performer: performer,
                                        reachability: FakeReachability(), now: { 0 })
        let token = try await db.upsertOutboundDraft(makeInput(), accountId: acc, now: 0)
        await svc.submit(clientToken: token)
        await performer.set(.success(nil))
        await svc.retry(clientToken: token)
        #expect(try await db.allOutbound(accountId: acc).isEmpty)
    }

    @Test func backoffGrowsAndCaps() {
        #expect(ComposerOutboxService.composerBackoffDelay(attempts: 1) == 2)
        #expect(ComposerOutboxService.composerBackoffDelay(attempts: 2) == 4)
        #expect(ComposerOutboxService.composerBackoffDelay(attempts: 20) == 300)
    }
}
```

- [ ] **Step 2: Run to verify failure** — type undefined. (`make project` first.)

- [ ] **Step 3: Implement the actor**

```swift
// SpudDataKit/Services/Outbox/ComposerOutboxService.swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import OSLog

private let logger = Logger.app

public struct ComposerOutboxFailure: Sendable, Equatable {
    public let clientToken: String
    public let kind: OutboundKind
}

public struct ComposerOutboxSuccess: Sendable, Equatable {
    public let clientToken: String
    public let kind: OutboundKind
    public let serverPostId: Int64?
}

public protocol ComposerOutboxServiceType: Actor {
    func submit(clientToken: String) async
    func retry(clientToken: String) async
    func discard(clientToken: String) async
    func drainOnce() async
    func drainAll() async
    func start() async
    var failureEvents: AsyncStream<ComposerOutboxFailure> { get }
    var successEvents: AsyncStream<ComposerOutboxSuccess> { get }
}

public actor ComposerOutboxService: ComposerOutboxServiceType {
    public static let maxAutoAttempts: Int64 = 8

    private let accountId: Int64
    private let appDatabase: AppDatabase
    private let performer: OutboundContentPerforming
    private let reachability: ReachabilityMonitoring
    private let now: @Sendable () -> Double

    private var failureContinuations: [UUID: AsyncStream<ComposerOutboxFailure>.Continuation] = [:]
    private var successContinuations: [UUID: AsyncStream<ComposerOutboxSuccess>.Continuation] = [:]
    private var started = false
    private var scheduledDrain: Task<Void, Never>?

    public init(
        accountId: Int64, appDatabase: AppDatabase, performer: OutboundContentPerforming,
        reachability: ReachabilityMonitoring, now: @escaping @Sendable () -> Double
    ) {
        self.accountId = accountId
        self.appDatabase = appDatabase
        self.performer = performer
        self.reachability = reachability
        self.now = now
    }

    public var failureEvents: AsyncStream<ComposerOutboxFailure> {
        AsyncStream { continuation in
            let id = UUID()
            failureContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in Task { await self?.removeFailure(id) } }
        }
    }

    public var successEvents: AsyncStream<ComposerOutboxSuccess> {
        AsyncStream { continuation in
            let id = UUID()
            successContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in Task { await self?.removeSuccess(id) } }
        }
    }

    private func removeFailure(_ id: UUID) { failureContinuations[id] = nil }
    private func removeSuccess(_ id: UUID) { successContinuations[id] = nil }
    private func emitFailure(_ f: ComposerOutboxFailure) { for c in failureContinuations.values { c.yield(f) } }
    private func emitSuccess(_ s: ComposerOutboxSuccess) { for c in successContinuations.values { c.yield(s) } }

    public func submit(clientToken: String) async {
        try? await appDatabase.markOutboundQueued(clientToken: clientToken, now: now())
        await drainOnce()
    }

    public func retry(clientToken: String) async {
        try? await appDatabase.markOutboundQueued(clientToken: clientToken, now: now())
        await drainOnce()
    }

    public func discard(clientToken: String) async {
        try? await appDatabase.deleteOutbound(clientToken: clientToken)
    }

    public func drainOnce() async {
        let due = (try? await appDatabase.dueOutbound(accountId: accountId, asOf: now())) ?? []
        await drain(records: due)
        await scheduleNextDrainIfNeeded()
    }

    public func drainAll() async {
        let all = (try? await appDatabase.dueOutbound(accountId: accountId, asOf: .greatestFiniteMagnitude)) ?? []
        await drain(records: all)
    }

    public func start() async {
        guard !started else { return }
        started = true
        await drainAll()
        let stream = await MainActor.run { reachability.statusStream }
        Task { [weak self] in
            var wasOnline: Bool?
            for await online in stream {
                if online, wasOnline != true { await self?.drainAll() }
                wasOnline = online
            }
        }
    }

    private func drain(records: [OutboundContentRecord]) async {
        for record in records {
            guard let id = record.id else { continue }
            let token = record.clientToken
            let kind = OutboundKind(rawValue: record.kind) ?? .comment

            // Dedup: if a prior attempt actually committed (response lost), adopt + skip.
            if kind == .comment,
               (try? await appDatabase.matchingServerCommentExists(
                   accountId: accountId, postServerId: record.postServerId,
                   parentCommentServerId: record.parentCommentServerId, body: record.body)) == true
            {
                try? await appDatabase.deleteOutbound(clientToken: token)
                emitSuccess(ComposerOutboxSuccess(clientToken: token, kind: kind, serverPostId: nil))
                continue
            }

            try? await appDatabase.markOutboundSending(id: id, now: now())
            do {
                let serverPostId = try await performer.perform(record)
                try? await appDatabase.deleteOutbound(clientToken: token)
                emitSuccess(ComposerOutboxSuccess(clientToken: token, kind: kind, serverPostId: serverPostId))
            } catch {
                let online = await MainActor.run { reachability.isOnline }
                switch OutboxFailureClass.classify(error, isOnline: online) {
                case .transient:
                    let attempts = record.attempts + 1
                    if attempts >= Self.maxAutoAttempts {
                        try? await appDatabase.markOutboundFailed(id: id, lastError: String(describing: error), now: now())
                        emitFailure(ComposerOutboxFailure(clientToken: token, kind: kind))
                    } else {
                        let next = now() + Self.composerBackoffDelay(attempts: attempts)
                        try? await appDatabase.markOutboundRetrying(
                            id: id, lastError: String(describing: error), nextAttemptAt: next, now: now())
                    }
                case .permanent:
                    try? await appDatabase.markOutboundFailed(id: id, lastError: String(describing: error), now: now())
                    emitFailure(ComposerOutboxFailure(clientToken: token, kind: kind))
                }
            }
        }
    }

    /// Self-schedule a single drain at the earliest pending backoff time, so a
    /// transient failure recovers without waiting for a reachability flip or relaunch.
    private func scheduleNextDrainIfNeeded() async {
        scheduledDrain?.cancel()
        let pending = (try? await appDatabase.allOutbound(accountId: accountId)) ?? []
        let nowValue = now()
        let nextTimes = pending.compactMap { row -> Double? in
            guard row.status == OutboundStatus.queued.rawValue, let n = row.nextAttemptAt, n > nowValue else { return nil }
            return n
        }
        guard let earliest = nextTimes.min() else { return }
        let delay = max(0, earliest - nowValue)
        scheduledDrain = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if Task.isCancelled { return }
            await self?.drainOnce()
        }
    }

    public static func composerBackoffDelay(attempts: Int64) -> Double {
        min(2.0 * pow(2.0, Double(max(0, attempts - 1))), 300)
    }
}
```

- [ ] **Step 4: Run to verify passing.** Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add SpudDataKit/Services/Outbox/ComposerOutboxService.swift SpudDataKitTests/ComposerOutboxServiceTests.swift
git commit -m "feat: add ComposerOutboxService durable send engine"
```

---

### Task 7: Wire the engine into `LemmyService` + `AccountScope`

**Files:**
- Modify: `SpudDataKit/Services/Lemmy/LemmyService.swift` (add lazy `composerOutboxService()` mirroring `outboxService()`; add high-level methods; add `composerFailureEvents()`/`composerSuccessEvents()`)
- Modify: `SpudDataKit/Services/Lemmy/LemmyServiceType.swift` (declare the new methods)
- Modify: `SpudDataKit/Services/Account/AccountScope.swift` (forward the two event streams)
- Test: extend `SpudDataKitTests` only if a fake `LemmyService` exists; otherwise rely on build + the engine tests.

**Interfaces:**
- Consumes: `ComposerOutboxService` (Task 6), `LemmyComposerPerformer` (Task 5), the existing `accountSiteIds()` and `outboxTask` memoization pattern, `reachability`.
- Produces on `LemmyServiceType`:
  - `func saveDraft(_ input: OutboundDraftInput) async throws -> String`
  - `func submitDraft(clientToken: String) async`
  - `func retryComposition(clientToken: String) async`
  - `func discardComposition(clientToken: String) async`
  - `func loadDraft(draftKey: String) async throws -> OutboundContentRecord?`
  - `func composerFailureEvents() async -> AsyncStream<ComposerOutboxFailure>`
  - `func composerSuccessEvents() async -> AsyncStream<ComposerOutboxSuccess>`
- Produces on `AccountScope`:
  - `func composerFailureEvents() async -> AsyncStream<ComposerOutboxFailure>`
  - `func composerSuccessEvents() async -> AsyncStream<ComposerOutboxSuccess>`

- [ ] **Step 1: Add the lazy service + methods to `LemmyService`**

Mirror the existing `outboxService()` (LemmyService.swift ~494–521). Add a memo property next to `outboxTask`:

```swift
    private var composerOutboxTask: Task<ComposerOutboxService?, Never>?

    private func composerOutbox() async -> ComposerOutboxService? {
        if let composerOutboxTask { return await composerOutboxTask.value }
        let task = Task<ComposerOutboxService?, Never> { [self] in
            guard let ids = try? await accountSiteIds() else { return nil }
            let performer = LemmyComposerPerformer(api: api, appDatabase: appDatabase, accountId: ids.0, siteId: ids.1)
            let service = ComposerOutboxService(
                accountId: ids.0, appDatabase: appDatabase, performer: performer,
                reachability: reachability, now: { Date().timeIntervalSince1970 }
            )
            await service.start()
            return service
        }
        composerOutboxTask = task
        let result = await task.value
        if result == nil { composerOutboxTask = nil }
        return result
    }

    public func saveDraft(_ input: OutboundDraftInput) async throws -> String {
        guard let ids = try await accountSiteIds() else {
            throw LemmyServiceError.internalInconsistency(description: "account row unavailable")
        }
        return try await appDatabase.upsertOutboundDraft(input, accountId: ids.0, now: Date().timeIntervalSince1970)
    }

    public func submitDraft(clientToken: String) async {
        await composerOutbox()?.submit(clientToken: clientToken)
    }

    public func retryComposition(clientToken: String) async {
        await composerOutbox()?.retry(clientToken: clientToken)
    }

    public func discardComposition(clientToken: String) async {
        await composerOutbox()?.discard(clientToken: clientToken)
    }

    public func loadDraft(draftKey: String) async throws -> OutboundContentRecord? {
        guard let ids = try await accountSiteIds() else { return nil }
        return try await appDatabase.loadOutboundDraft(accountId: ids.0, draftKey: draftKey)
    }

    public func composerFailureEvents() async -> AsyncStream<ComposerOutboxFailure> {
        guard let svc = await composerOutbox() else { return AsyncStream { $0.finish() } }
        return await svc.failureEvents
    }

    public func composerSuccessEvents() async -> AsyncStream<ComposerOutboxSuccess> {
        guard let svc = await composerOutbox() else { return AsyncStream { $0.finish() } }
        return await svc.successEvents
    }
```

> NOTE for implementer: confirm the names `api`, `appDatabase`, `reachability`, `accountSiteIds()`, `outboxTask` exist on `LemmyService` as shown in the verbatim `outboxService()` extract. Add `composerOutboxTask` next to `outboxTask`.

- [ ] **Step 2: Declare the methods on `LemmyServiceType`**

Add the 7 method signatures to the protocol in `LemmyServiceType.swift` (find the protocol that already declares `createComment`/`createPost`/`setSaved`).

- [ ] **Step 3: Forward the two event streams on `AccountScope`**

In `AccountScope.swift`, mirror the existing `outboxFailureEvents()` forwarder:

```swift
    public func composerFailureEvents() async -> AsyncStream<ComposerOutboxFailure> {
        await lemmyService.composerFailureEvents()
    }

    public func composerSuccessEvents() async -> AsyncStream<ComposerOutboxSuccess> {
        await lemmyService.composerSuccessEvents()
    }
```

- [ ] **Step 4: Build**

Run: `make project && python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud`
Expected: build succeeds, 0 new warnings.

- [ ] **Step 5: Commit**

```bash
git add SpudDataKit/Services/Lemmy/LemmyService.swift SpudDataKit/Services/Lemmy/LemmyServiceType.swift SpudDataKit/Services/Account/AccountScope.swift
git commit -m "feat: wire ComposerOutboxService into LemmyService and AccountScope"
```

---

## PHASE 2 — Comment optimism (inline tree + drafts)

### Task 8: Draft autosave + enqueue in `ComposerViewModel`

**Files:**
- Modify: `Spud/Scenes/Composer/ComposerViewModel.swift`
- Test: none (UI view model; covered by manual + the snapshot/UI tasks). Build must pass.

**Interfaces:**
- Consumes: `accountScope.lemmyService.saveDraft/submitDraft/loadDraft`, `OutboundDraftInput`, `OutboundContentRecord.commentDraftKey`.
- Produces: `ComposerViewModel` now (a) loads a draft on init/appear and prefills `bodyText`; (b) debounce-saves the draft as `bodyText` changes; (c) `post()` saves the draft then submits it to the queue and reports `.finished` immediately (optimistic); (d) `func flushDraft() async` for dismiss/background; (e) `func discardDraft() async`.

- [ ] **Step 1: Add draft plumbing**

Replace `ComposerViewModel.post()` and add draft methods. Key changes (keep `ComposerSubmissionState`; `.finished` now means "queued", and the sheet dismisses immediately):

```swift
    @ObservationIgnored private var clientToken: String?
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    private var draftKey: String? {
        guard let postId = target.serverPostId else { return nil } // comments/post-replies only here
        return OutboundContentRecord.commentDraftKey(
            postServerId: Int64(postId),
            parentCommentServerId: target.parentCommentId.map { Int64($0) }
        )
    }

    func loadExistingDraft() async {
        guard let draftKey else { return }
        if let row = try? await accountScope.lemmyService.loadDraft(draftKey: draftKey), !row.body.isEmpty {
            clientToken = row.clientToken
            bodyText = row.body
        }
    }

    func bodyDidChange() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if Task.isCancelled { return }
            await self?.flushDraft()
        }
    }

    func flushDraft() async {
        guard let postId = target.serverPostId else { return }
        let trimmed = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let input = OutboundDraftInput(
            kind: .comment, body: bodyText, postServerId: Int64(postId),
            parentCommentServerId: target.parentCommentId.map { Int64($0) },
            communityServerId: nil, title: nil, url: nil, nsfw: false, postType: 0
        )
        clientToken = try? await accountScope.lemmyService.saveDraft(input)
    }

    func discardDraft() async {
        if let token = clientToken {
            await accountScope.lemmyService.discardComposition(clientToken: token)
            clientToken = nil
        }
    }

    func post() async {
        let content = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        await flushDraft()                       // ensure the draft row exists with latest text
        guard let token = clientToken else {
            submissionState = .failed(message: NSLocalizedString("Couldn't save your comment.", comment: "Composer enqueue failure"))
            return
        }
        await accountScope.lemmyService.submitDraft(clientToken: token)
        clientToken = nil                        // ownership passes to the queue
        submissionState = .finished              // dismiss immediately; queue + tree overlay take over
    }
```

- [ ] **Step 2: Hook the VC** (next task wires `bodyDidChange`, `loadExistingDraft`, dismiss confirmation). Build now to confirm the VM compiles:

Run: `make project && python3 .../build_and_test.py --scheme Spud`. Expected: build succeeds (the VC still calls `viewModel.post()`; unused new methods are fine).

- [ ] **Step 3: Commit**

```bash
git add Spud/Scenes/Composer/ComposerViewModel.swift
git commit -m "feat: durable comment drafts and optimistic enqueue in ComposerViewModel"
```

---

### Task 9: `ComposerViewController` — prefill, autosave hook, Mail-style dismiss

**Files:**
- Modify: `Spud/Scenes/Composer/ComposerViewController.swift`

**Interfaces:**
- Consumes: `viewModel.loadExistingDraft()`, `bodyDidChange()`, `flushDraft()`, `discardDraft()`.

- [ ] **Step 1: Prefill + autosave**

In `viewDidLoad` after `bindViewModel()`, load any draft and reflect it into the editor; route text changes through `bodyDidChange()`:

```swift
        editorView.onTextChange = { [weak self] text in
            self?.viewModel.bodyText = text
            self?.viewModel.bodyDidChange()
        }
        Task { @MainActor [weak self] in
            await self?.viewModel.loadExistingDraft()
            self?.editorView.text = self?.viewModel.bodyText ?? ""
        }
```

- [ ] **Step 2: Mail-style dismiss + background flush**

Replace `cancelTapped()` and add presentation-controller dismiss handling:

```swift
    @objc private func cancelTapped() {
        view.endEditing(true)
        let trimmed = viewModel.bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { dismiss(animated: true); return }
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: NSLocalizedString("Save Draft", comment: "Composer keep-draft action"), style: .default) { [weak self] _ in
            Task { await self?.viewModel.flushDraft(); await MainActor.run { self?.dismiss(animated: true) } }
        })
        sheet.addAction(UIAlertAction(title: NSLocalizedString("Delete Draft", comment: "Composer discard-draft action"), style: .destructive) { [weak self] _ in
            Task { await self?.viewModel.discardDraft(); await MainActor.run { self?.dismiss(animated: true) } }
        })
        sheet.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel dismiss"), style: .cancel))
        present(sheet, animated: true)
    }
```

Also flush on background — in `viewDidLoad` register:

```swift
        NotificationCenter.default.addObserver(
            forName: UIScene.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { await self?.viewModel.flushDraft() }
        }
```

> NOTE: keep the `apply(submissionState:)` `.finished` branch as-is (it dismisses). The `.submitting` spinner branch is now effectively unused for the optimistic path (`post()` jumps straight to `.finished`), but leave it — it harms nothing and the DM path still uses the blocking flow until migrated.

- [ ] **Step 3: Build + manual smoke**

Run: `make project && python3 .../build_and_test.py --scheme Spud`. Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Spud/Scenes/Composer/ComposerViewController.swift
git commit -m "feat: composer draft prefill, autosave, Mail-style dismiss"
```

---

### Task 10: Pending comment cell rendering

**Files:**
- Create: `Spud/Scenes/PostDetail/Content/Comment/PendingCommentCellState.swift`
- Modify: `Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentCell.swift`
- Test: snapshot (Task 12).

**Interfaces:**
- Produces:
  - `struct PendingCommentCellState: Equatable { let clientToken: String; let body: String; let depth: Int; let status: Status; enum Status { case sending; case failed } }`
  - `PostDetailCommentCell.configurePending(_ state: PendingCommentCellState)` — renders the body via the existing body view, sets the subtitle line to "Sending…" or "Failed — tap to retry", dims the cell (`contentView.alpha = 0.6` for sending), hides vote/save/reply affordances, applies the depth indent the same way a normal comment does.

- [ ] **Step 1: Create the state type**

```swift
// Spud/Scenes/PostDetail/Content/Comment/PendingCommentCellState.swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

struct PendingCommentCellState: Equatable {
    enum Status: Equatable { case sending, failed }
    let clientToken: String
    let body: String
    let depth: Int
    let status: Status
}
```

- [ ] **Step 2: Add `configurePending` to the cell**

Open `PostDetailCommentCell.swift`. Add a method that reuses the existing `bodyView`, `subtitleLabel`, indent constraint, and badge-clearing logic the regular `configure(with:imageService:)` uses (read that method first for the exact view names — `authorLabel`, `subtitleLabel`, `bodyView`, `clearBadges()`, the depth/indent mechanism). Concretely:

```swift
    func configurePending(_ state: PendingCommentCellState, imageService: ImageServiceType) {
        clearBadges()
        authorLabel.attributedText = NSAttributedString(
            string: NSLocalizedString("You", comment: "Pending comment author label"),
            attributes: [.font: UIFont.preferredFont(forTextStyle: .subheadline)]
        )
        let statusText: String
        switch state.status {
        case .sending: statusText = NSLocalizedString("Sending\u{2026}", comment: "Pending comment status")
        case .failed:  statusText = NSLocalizedString("Failed \u{2014} tap to retry", comment: "Failed comment status")
        }
        subtitleLabel.attributedText = NSAttributedString(
            string: statusText,
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .caption1),
                .foregroundColor: state.status == .failed ? UIColor.systemRed : UIColor.secondaryLabel,
            ]
        )
        subtitleLabel.accessibilityLabel = statusText
        messageLabel.attributedText = nil
        messageLabel.isHidden = true
        bodyView.isHidden = false
        // Parse + set body the same way configure(with:) does. Reuse the existing
        // MarkdownBlockCache + setBlocks path; see configure(with:) for the call.
        configureBody(markdown: state.body, imageService: imageService) // <- implement via the same code configure(with:) uses
        applyDepthIndent(depth: state.depth)                            // <- reuse the existing indent setter
        contentView.alpha = state.status == .sending ? 0.6 : 1.0
    }
```

> NOTE for implementer: `configureBody(markdown:imageService:)` and `applyDepthIndent(depth:)` above are stand-ins for whatever the cell already does inside `configure(with:imageService:)` to (a) render the markdown body and (b) set the leading indent for `depth`. Extract those two snippets from `configure(with:)` into small private helpers and call them from both methods (DRY). Do not duplicate the markdown-parsing block.

- [ ] **Step 3: Build**

Run: `make project && python3 .../build_and_test.py --scheme Spud`. Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Spud/Scenes/PostDetail/Content/Comment/PendingCommentCellState.swift Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentCell.swift
git commit -m "feat: pending/failed comment cell rendering"
```

---

### Task 11: Overlay outbound comments into the post-detail tree

**Files:**
- Create: `SpudDataKit/Services/AppDatabase/OutboundContentObservations.swift`
- Modify: `Spud/Scenes/PostDetail/Content/PostDetailViewController.swift`
- Test: snapshot (Task 12) + manual.

**Interfaces:**
- Consumes: `allOutbound`, `OutboundContentRecord`, the diffable `Item`/`Section`, `viewModel.visibleCommentTree()`, `commentRowsByElementId`.
- Produces:
  - `AppDatabase.observeOutboundComments(postServerId: Int64, accountKeychainId: String) -> AsyncStream<[OutboundContentRecord]>` (comment-kind rows for this post + account, status != sent; ordered createdAt).
  - In the VC: a second observation task storing `pendingOutboundComments: [OutboundContentRecord]`, a merge that inserts synthetic pending items into the snapshot under their parent, a `pendingStateByElementId: [Int64: PendingCommentCellState]` map, a cell-provider branch for synthetic ids, and tap handling (Retry/Edit/Discard).

- [ ] **Step 1: Add the observation**

```swift
// SpudDataKit/Services/AppDatabase/OutboundContentObservations.swift
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
    /// Outbound comment rows for `postServerId` belonging to `accountKeychainId`.
    func observeOutboundComments(postServerId: Int64, accountKeychainId: String) -> AsyncStream<[OutboundContentRecord]> {
        let observation = ValueObservation
            .tracking { db -> [OutboundContentRecord] in
                try OutboundContentRecord
                    .filter(Column("kind") == OutboundKind.comment.rawValue)
                    .filter(Column("postServerId") == postServerId)
                    .filter(sql: "accountId IN (SELECT id FROM account WHERE accountKeychainId = ?)", arguments: [accountKeychainId])
                    .order(Column("createdAt").asc)
                    .fetchAll(db)
            }
            .removeDuplicates()
        return AsyncStream { continuation in
            let cancellable = observation.start(in: writer, scheduling: .async(onQueue: .global(qos: .userInitiated))) { error in
                logger.error("observeOutboundComments failed: \(String(describing: error), privacy: .public)")
                continuation.finish()
            } onChange: { value in
                continuation.yield(value)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    /// All outbound rows for `accountKeychainId` (Drafts & Outbox list).
    func observeOutboundContent(accountKeychainId: String) -> AsyncStream<[OutboundContentRecord]> {
        let observation = ValueObservation
            .tracking { db -> [OutboundContentRecord] in
                try OutboundContentRecord
                    .filter(sql: "accountId IN (SELECT id FROM account WHERE accountKeychainId = ?)", arguments: [accountKeychainId])
                    .order(Column("createdAt").desc)
                    .fetchAll(db)
            }
            .removeDuplicates()
        return AsyncStream { continuation in
            let cancellable = observation.start(in: writer, scheduling: .async(onQueue: .global(qos: .userInitiated))) { error in
                logger.error("observeOutboundContent failed: \(String(describing: error), privacy: .public)")
                continuation.finish()
            } onChange: { value in
                continuation.yield(value)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }
}
```

- [ ] **Step 2: Merge into the snapshot (PostDetailViewController)**

Add state + a second observation, started alongside `startCommentObservation`:

```swift
    private var pendingOutboundComments: [OutboundContentRecord] = []
    private var pendingStateByElementId: [Int64: PendingCommentCellState] = [:]
    private var pendingTokenByElementId: [Int64: String] = [:]
    private var outboundObservationTask: Task<Void, Never>?

    private func startOutboundObservation() {
        outboundObservationTask?.cancel()
        let postServerId = Int64(viewModel.serverPostId)
        let keychainId = viewModel.accountKeychainId
        outboundObservationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await rows in appDatabase.observeOutboundComments(postServerId: postServerId, accountKeychainId: keychainId) {
                if Task.isCancelled { break }
                pendingOutboundComments = rows.filter { $0.status != OutboundStatus.draft.rawValue }
                applySnapshot(animated: true)
            }
        }
    }
```

Call `startOutboundObservation()` everywhere `startCommentObservation(postRowId:)` is called.

In `applySnapshot()`, after computing `let commentItems = visible.rows.map { Item.comment(elementId: $0.id) }`, build merged items that splice pending nodes. Synthetic element ids use a high negative base to avoid collision with real row ids:

```swift
        // Map server comment id -> visible element id, to place replies under parents.
        var elementIdByServerCommentId: [Int64: Int64] = [:]
        for row in visible.rows {
            if let scid = row.serverCommentId { elementIdByServerCommentId[scid] = row.id }
        }
        let depthByElementId = Dictionary(uniqueKeysWithValues: visible.rows.map { ($0.id, Int($0.depth)) })

        pendingStateByElementId.removeAll()
        pendingTokenByElementId.removeAll()
        var mergedItems: [Item] = []
        // top-level pending = parentCommentServerId nil; nested = under its parent element.
        func pendingItem(for record: OutboundContentRecord, depth: Int) -> Item {
            let elementId = -(1_000_000 + (record.id ?? 0))
            let status: PendingCommentCellState.Status =
                record.status == OutboundStatus.failed.rawValue ? .failed : .sending
            pendingStateByElementId[elementId] = PendingCommentCellState(
                clientToken: record.clientToken, body: record.body, depth: depth, status: status)
            pendingTokenByElementId[elementId] = record.clientToken
            return .comment(elementId: elementId)
        }
        // Build the comment list, appending nested pending replies right after their parent.
        for row in visible.rows {
            mergedItems.append(.comment(elementId: row.id))
            if let scid = row.serverCommentId {
                for p in pendingOutboundComments where p.parentCommentServerId == scid {
                    mergedItems.append(pendingItem(for: p, depth: Int(row.depth) + 1))
                }
            }
        }
        // Top-level pending (and orphans whose parent isn't loaded) go at the end.
        for p in pendingOutboundComments where p.parentCommentServerId == nil
            || (p.parentCommentServerId.map { elementIdByServerCommentId[$0] == nil } ?? false) {
            mergedItems.append(pendingItem(for: p, depth: 0))
        }
        let sectionItems = Self.commentsSectionItems(background: background, commentItems: mergedItems)
```

Replace the existing `commentItems`/`sectionItems` usage with `mergedItems`. Keep `reconfigureItems(mergedItems)`.

- [ ] **Step 3: Cell provider branch + tap actions**

In the `.comment(elementId)` case of the cell provider, branch on pending state:

```swift
                if let pending = self?.pendingStateByElementId[elementId] {
                    cell.configurePending(pending, imageService: imageService)
                    cell.pendingTapped = { [weak self] in self?.handlePendingTap(elementId: elementId) }
                    return cell
                }
```

Add `var pendingTapped: (() -> Void)?` to `PostDetailCommentCell` (invoked on `contentView` tap when in pending mode — add a tap gesture installed in `configurePending`). Then in the VC:

```swift
    private func handlePendingTap(elementId: Int64) {
        guard let token = pendingTokenByElementId[elementId],
              let state = pendingStateByElementId[elementId], state.status == .failed else { return }
        let sheet = UIAlertController(title: nil, message: state.body, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: NSLocalizedString("Retry", comment: "Retry failed comment"), style: .default) { [weak self] _ in
            Task { await self?.viewModel.accountScope.lemmyService.retryComposition(clientToken: token) }
        })
        sheet.addAction(UIAlertAction(title: NSLocalizedString("Edit", comment: "Edit failed comment"), style: .default) { [weak self] _ in
            self?.editFailedComment(token: token, body: state.body)
        })
        sheet.addAction(UIAlertAction(title: NSLocalizedString("Discard", comment: "Discard failed comment"), style: .destructive) { [weak self] _ in
            Task { await self?.viewModel.accountScope.lemmyService.discardComposition(clientToken: token) }
        })
        sheet.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel"), style: .cancel))
        present(sheet, animated: true)
    }

    private func editFailedComment(token: String, body: String) {
        // Reopen the composer for the same target; it will load this draft after we
        // flip the failed row back to a draft. Simplest path: discard the failed
        // send, then present the composer pre-seeded with `body`.
        Task { @MainActor in
            await viewModel.accountScope.lemmyService.discardComposition(clientToken: token)
            // Re-present composer; it starts empty, so seed via a one-shot.
            replyToPost() // or replyToComment(...) depending on the row; see NOTE
        }
    }
```

> NOTE for implementer: `editFailedComment` needs the original target (top-level vs reply-to-parent). Carry `parentCommentServerId` into `pendingStateByElementId` (add the field) so you can call `replyToComment(serverCommentId:)` vs `replyToPost()`, and seed the composer's initial text. The cleanest seed is to add an optional `initialBody` to `ComposerViewController.makeSheet`/`ComposerViewModel.init` and set `bodyText` from it when no saved draft exists.

- [ ] **Step 4: Build + manual smoke (record/verify in Task 12).**

Run: `make project && python3 .../build_and_test.py --scheme Spud`. Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add SpudDataKit/Services/AppDatabase/OutboundContentObservations.swift Spud/Scenes/PostDetail/Content/PostDetailViewController.swift Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentCell.swift
git commit -m "feat: overlay optimistic comments into the post-detail tree"
```

---

### Task 12: Snapshot coverage — pending/failed comment cell

**Files:**
- Create: `SpudSnapshotTests/PostDetailPendingCommentSnapshotTests.swift`
- Snapshots: recorded under `SpudSnapshotTests/__Snapshots__/PostDetailPendingCommentSnapshotTests/`

**Interfaces:**
- Consumes: `PostDetailCommentCell.configurePending`, the snapshot harness conventions used by `PostDetailCommentSnapshotTests` (read that file for the exact `assertSnapshot` setup, trait collection, width).

- [ ] **Step 1: Write the snapshot test** (mirror `PostDetailCommentSnapshotTests` structure)

```swift
// SpudSnapshotTests/PostDetailPendingCommentSnapshotTests.swift
import SnapshotTesting
import UIKit
import XCTest
@testable import Spud
@testable import SpudDataKit

final class PostDetailPendingCommentSnapshotTests: XCTestCase {
    func test_pendingComment_sending_light() {
        let cell = makeCell(status: .sending)
        assertSnapshot(of: cell, as: .image(traits: .init(userInterfaceStyle: .light)), named: "light")
    }
    func test_pendingComment_sending_dark() {
        let cell = makeCell(status: .sending)
        assertSnapshot(of: cell, as: .image(traits: .init(userInterfaceStyle: .dark)), named: "dark")
    }
    func test_pendingComment_failed_light() {
        let cell = makeCell(status: .failed)
        assertSnapshot(of: cell, as: .image(traits: .init(userInterfaceStyle: .light)), named: "light")
    }
    func test_pendingComment_failed_dark() {
        let cell = makeCell(status: .failed)
        assertSnapshot(of: cell, as: .image(traits: .init(userInterfaceStyle: .dark)), named: "dark")
    }

    private func makeCell(status: PendingCommentCellState.Status) -> PostDetailCommentCell {
        let cell = PostDetailCommentCell(style: .default, reuseIdentifier: nil)
        cell.frame = CGRect(x: 0, y: 0, width: 390, height: 120)
        cell.configurePending(
            PendingCommentCellState(clientToken: "t", body: "This is my reply, sending now.", depth: 1, status: status),
            imageService: StaticImageService()
        )
        cell.layoutIfNeeded()
        return cell
    }
}
```

> NOTE for implementer: match the EXACT `assertSnapshot` invocation style of `PostDetailCommentSnapshotTests.swift` (it may use `.image(on:)` configs and a specific naming scheme). `StaticImageService()` is the existing test double mentioned in CLAUDE.md.

- [ ] **Step 2: Record (first run fails by design)**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan SpudSnapshots -only-testing:SpudSnapshotTests/PostDetailPendingCommentSnapshotTests -destination 'platform=iOS Simulator,name=iPhone 14 Pro' -skipPackagePluginValidation -skipMacroValidation test`
Expected: FAIL — "No reference image" (records 4 PNGs).

- [ ] **Step 3: Verify (second run passes)**

Re-run the same command. Expected: PASS. Then `git add` the new PNGs (the git-annex clean filter stores them — do NOT `git annex restage`; see CLAUDE.md).

- [ ] **Step 4: Commit**

```bash
git add SpudSnapshotTests/PostDetailPendingCommentSnapshotTests.swift
git add SpudSnapshotTests/__Snapshots__/PostDetailPendingCommentSnapshotTests
git commit -m "test: snapshots for pending/failed comment cell"
```

---

## PHASE 3 — Post optimism (pending post detail + drafts)

### Task 13: Draft autosave + enqueue in `NewPostViewModel`

**Files:**
- Modify: `Spud/Scenes/Composer/NewPostViewModel.swift`

**Interfaces:**
- Consumes: `accountScope.lemmyService.saveDraft/submitDraft/loadDraft/discardComposition`, `OutboundDraftInput`, `OutboundContentRecord.postDraftKey`.
- Produces: `NewPostViewModel` loads/saves a post draft keyed by community; `submit()` saves the draft, enqueues it, and reports a new state `.queued(clientToken: String)` so the VC can dismiss and push the pending post screen. Add `func bodyDidChange()`, `flushDraft()`, `discardDraft()`, `loadExistingDraft()`.

- [ ] **Step 1: Add `.queued` to `NewPostSubmissionState`**

```swift
enum NewPostSubmissionState: Equatable {
    case editing
    case uploadingImage
    case submitting
    case finished(serverPostId: Components.Schemas.PostID)   // kept for any non-optimistic callers
    case queued(clientToken: String)                          // NEW: optimistic enqueue
    case failed(message: String)
}
```

Update `canPost`/`isBusy` switch arms to include `.queued` (treat like `.editing` for `isBusy=false`; `canPost` requires `== .editing`).

- [ ] **Step 2: Draft plumbing + submit**

```swift
    @ObservationIgnored private var clientToken: String?
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    private var draftKey: String { OutboundContentRecord.postDraftKey(communityServerId: community.map { Int64($0.id) }) }

    private func currentInput() -> OutboundDraftInput {
        OutboundDraftInput(
            kind: .post, body: bodyText, postServerId: nil, parentCommentServerId: nil,
            communityServerId: community.map { Int64($0.id) },
            title: titleText, url: urlText.isEmpty ? nil : urlText, nsfw: nsfw, postType: Int64(postType.rawValue)
        )
    }

    func loadExistingDraft() async {
        if let row = try? await accountScope.lemmyService.loadDraft(draftKey: draftKey),
           !(row.title ?? "").isEmpty || !row.body.isEmpty {
            clientToken = row.clientToken
            titleText = row.title ?? ""
            bodyText = row.body
            urlText = row.url ?? ""
            nsfw = row.nsfw
            postType = NewPostType(rawValue: Int(row.postType)) ?? .text
        }
    }

    func bodyDidChange() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if Task.isCancelled { return }
            await self?.flushDraft()
        }
    }

    func flushDraft() async {
        guard community != nil else { return }
        let hasContent = !titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasContent else { return }
        clientToken = try? await accountScope.lemmyService.saveDraft(currentInput())
    }

    func discardDraft() async {
        if let token = clientToken { await accountScope.lemmyService.discardComposition(clientToken: token); clientToken = nil }
    }

    func submit() async {
        let title = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, community != nil else { return }
        await flushDraft()
        guard let token = clientToken else {
            submissionState = .failed(message: NSLocalizedString("Couldn't save your post.", comment: "New post enqueue failure"))
            return
        }
        await accountScope.lemmyService.submitDraft(clientToken: token)
        clientToken = nil
        submissionState = .queued(clientToken: token)
    }
```

- [ ] **Step 3: Build** — `make project && python3 .../build_and_test.py --scheme Spud`. Expected: build succeeds (VC still handles `.finished`; you wire `.queued` next task).

- [ ] **Step 4: Commit**

```bash
git add Spud/Scenes/Composer/NewPostViewModel.swift
git commit -m "feat: durable post drafts and optimistic enqueue in NewPostViewModel"
```

---

### Task 14: `PendingPostViewController` + swap-on-success

**Files:**
- Create: `Spud/Scenes/Composer/PendingPostViewController.swift`
- Modify: `Spud/Scenes/Composer/NewPostViewController.swift` (handle `.queued`, prefill, autosave hook, Mail-style dismiss)
- Modify: `Spud/Scenes/MainWindow/MainWindow.swift` (push pending post detail; swap to real on success)

**Interfaces:**
- Consumes: `OutboundContentRecord` (read the draft by clientToken to render), `accountScope.composerSuccessEvents()` (filter by clientToken → `serverPostId`), `display(serverPostId:accountKeychainId:)`, `pushIntoCurrentContext`, navigation `setViewControllers`.
- Produces: `PendingPostViewController(clientToken:accountKeychainId:dependencies:)` that renders title/body/url + a `Sending…`/`Failed` banner, observes outbound content for its token, and calls `onResolvedPost: (Components.Schemas.PostID) -> Void` when its send succeeds; `onFailedRetry`/`onFailedEdit`/`onFailedDiscard` for the failed banner.

- [ ] **Step 1: Create `PendingPostViewController`**

A focused VC. Renders from a `OutboundContentRecord` (fetched via `appDatabase.observeOutboundContent(accountKeychainId:)` filtered to its `clientToken`). Layout: reuse the post-detail header view if cheap, else a simple title label + markdown body view + URL row + a status banner. Banner states:
- queued/sending → spinner + "Sending…"
- failed → red "Couldn't post" + Retry / Edit / Discard buttons

On observing its row vanish (deleted) it does nothing (success arrives via the success-event subscription, which provides the serverPostId). Wire:

```swift
final class PendingPostViewController: UIViewController {
    typealias OwnDependencies = HasAppDatabase & HasAccountService & HasImageService
    typealias Dependencies = OwnDependencies

    var onResolvedPost: ((Components.Schemas.PostID) -> Void)?

    private let clientToken: String
    private let accountKeychainId: String
    private let dependencies: OwnDependencies
    private var observationTasks: [Task<Void, Never>] = []

    init(clientToken: String, accountKeychainId: String, dependencies: Dependencies) {
        self.clientToken = clientToken
        self.accountKeychainId = accountKeychainId
        self.dependencies = dependencies
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    deinit { observationTasks.forEach { $0.cancel() } }

    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
        // Render the draft fields.
        observationTasks.append(Task { @MainActor [weak self] in
            guard let self else { return }
            for await rows in dependencies.appDatabase.observeOutboundContent(accountKeychainId: accountKeychainId) {
                guard let row = rows.first(where: { $0.clientToken == clientToken }) else { continue }
                render(row)
            }
        })
        // Swap to the real post on success.
        observationTasks.append(Task { @MainActor [weak self] in
            guard let self else { return }
            let scope = dependencies.accountService.scope(forAccountKeychainId: accountKeychainId)
            for await success in await scope.composerSuccessEvents() {
                guard success.clientToken == clientToken, let serverPostId = success.serverPostId else { continue }
                onResolvedPost?(Components.Schemas.PostID(serverPostId))
                break
            }
        })
    }
    // render(_:), setup(), retry/edit/discard button handlers calling
    // scope.lemmyService.retryComposition/discardComposition(clientToken:)...
}
```

> NOTE for implementer: keep `render(_:)` simple and reuse existing post-detail header/body views where convenient. The success subscription must be started in `viewDidLoad` (before/at push time) so a fast send isn't missed; if you observe a race in testing, also check at appear time whether the row is already gone AND a matching post now exists, and resolve via `display`.

- [ ] **Step 2: `NewPostViewController` — handle `.queued`, prefill, autosave, dismiss**

Mirror Task 9 for the post composer: route text changes through `viewModel.bodyDidChange()`, `loadExistingDraft()` on appear, Mail-style dismiss. Add a `.queued` arm to the state handler:

```swift
        case let .queued(clientToken):
            view.endEditing(true)
            Haptics.success()
            dismiss(animated: true) { [onQueued] in onQueued?(clientToken) }
```

Add `var onQueued: ((String) -> Void)?` next to the existing `onPosted`.

- [ ] **Step 3: `MainWindow` — push pending detail, swap on success**

Where `NewPostViewController` is presented, set `onQueued` to push the pending screen:

```swift
        newPostVC.onQueued = { [weak self] clientToken in
            guard let self else { return }
            let pending = PendingPostViewController(
                clientToken: clientToken, accountKeychainId: keychainId, dependencies: dependencies.nested)
            pending.onResolvedPost = { [weak self] serverPostId in
                guard let self else { return }
                // Replace the pending screen in-place with the real post detail.
                let real = PostDetailOrEmptyViewController(
                    serverPostId: serverPostId, accountKeychainId: keychainId, dependencies: dependencies.nested)
                replaceTop(pending, with: real)
            }
            pushIntoCurrentContext(pending)
        }
```

Add a `replaceTop(_:with:)` helper that finds `pending`'s navigation controller and does `setViewControllers(replacing the last entry, animated: false)`; if `pending` is no longer in any stack (user navigated away), do nothing.

> NOTE for implementer: read the existing `onPosted` wiring in `MainWindow`/wherever `NewPostViewController.makeSheet` is presented to find `keychainId`, `dependencies.nested`, and the presentation site. Keep `onPosted` too if any non-optimistic caller remains; the optimistic path uses `onQueued`.

- [ ] **Step 4: Build + manual smoke** — `make project && python3 .../build_and_test.py --scheme Spud`. Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Spud/Scenes/Composer/PendingPostViewController.swift Spud/Scenes/Composer/NewPostViewController.swift Spud/Scenes/MainWindow/MainWindow.swift
git commit -m "feat: pending post detail with swap-on-success"
```

---

### Task 15: Snapshot coverage — pending post screen

**Files:**
- Create: `SpudSnapshotTests/PendingPostSnapshotTests.swift`
- Snapshots under `__Snapshots__/PendingPostSnapshotTests/`

- [ ] **Step 1: Write snapshot tests** for the pending post screen in `sending` and `failed` states (light/dark), constructing `PendingPostViewController` with an in-memory `AppDatabase` seeded with one outbound post row (status sending; status failed). Use `.image(on: .iPhone13Pro)` with a `size:` so the full content is captured (per CLAUDE.md). Mirror `InstanceDetailSnapshotTests` for the screen-snapshot config.

- [ ] **Step 2: Record (fails).** Run the SpudSnapshots command targeting only this class. Expected: FAIL (records PNGs).
- [ ] **Step 3: Verify (passes).** Re-run. Expected: PASS. `git add` PNGs (no annex restage).
- [ ] **Step 4: Commit**

```bash
git add SpudSnapshotTests/PendingPostSnapshotTests.swift SpudSnapshotTests/__Snapshots__/PendingPostSnapshotTests
git commit -m "test: snapshots for pending post screen"
```

---

## PHASE 4 — Recovery surface + global wiring

### Task 16: "Drafts & Outbox" list

**Files:**
- Create: `Spud/Scenes/DraftsOutbox/OutboundContentListViewModel.swift`
- Create: `Spud/Scenes/DraftsOutbox/OutboundContentListViewController.swift`
- Snapshot: `SpudSnapshotTests/OutboundContentListSnapshotTests.swift`

**Interfaces:**
- Consumes: `appDatabase.observeOutboundContent(accountKeychainId:)`, `accountScope.lemmyService.retryComposition/discardComposition`.
- Produces: a grouped list (Failed / Sending / Drafts), each row showing kind + target + snippet + status with swipe/menu Retry / Edit / Discard.

- [ ] **Step 1: View model** — `@Observable` holding `[OutboundContentRecord]`, grouped + sorted (Failed first), with `retry`/`discard` calling through the scope. Bind via `ObservationStream` per the codebase convention.
- [ ] **Step 2: View controller** — a `UITableView` (or list) with three sections; reuse subtitle cells. Title "Drafts & Outbox".
- [ ] **Step 3: Snapshot test** — populate an in-memory DB with one failed, one sending, one draft row; snapshot the screen light/dark. Record → verify → `git add` PNGs.
- [ ] **Step 4: Build + commit**

```bash
make project && python3 .../build_and_test.py --scheme Spud
git add Spud/Scenes/DraftsOutbox SpudSnapshotTests/OutboundContentListSnapshotTests.swift SpudSnapshotTests/__Snapshots__/OutboundContentListSnapshotTests
git commit -m "feat: Drafts & Outbox recovery list"
```

---

### Task 17: Global failure toast + entry points

**Files:**
- Modify: `Spud/Scenes/MainWindow/MainWindow.swift`
- Modify: the account/preferences screen (find where "Account" rows are listed) to add a "Drafts & Outbox" entry.

**Interfaces:**
- Consumes: `scope.composerFailureEvents()` (Task 7), the existing `ToastPresenter`, the `outboxFailureToastTask` pattern (MainWindow ~305).
- Produces: a `composerFailureToastTask` that shows `Couldn't post — Retry / View`; "View" opens the Drafts & Outbox list; "Retry" calls `retryComposition`.

- [ ] **Step 1: Add the failure subscription** mirroring `outboxFailureToastTask`:

```swift
        composerFailureToastTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let events = await scope.composerFailureEvents()
            for await failure in events {
                guard currentDefaultAccountKeychainId == keychainId else { break }
                presentComposerFailureToast(failure)
            }
        }
```

`presentComposerFailureToast` shows a toast with a "View" action that pushes `OutboundContentListViewController`. (If `ToastPresenter` supports an action button, use it; otherwise show a non-blocking toast "Couldn't post — see Drafts & Outbox" and rely on the list entry.)

- [ ] **Step 2: Add the "Drafts & Outbox" entry** to the account/preferences screen, pushing `OutboundContentListViewController` for the current account.
- [ ] **Step 3: Build + commit**

```bash
make project && python3 .../build_and_test.py --scheme Spud
git add Spud/Scenes/MainWindow/MainWindow.swift Spud/Scenes/<preferences-file>.swift
git commit -m "feat: composer failure toast and Drafts & Outbox entry points"
```

---

## PHASE 5 — Docs

### Task 18: Update feature docs

**Files:**
- Modify: `docs/features/draft-persistence.md`, `docs/features/replying.md`, `docs/features/new-post.md`

- [ ] **Step 1: Rewrite `draft-persistence.md`** — from "in-memory only" to durable per-target auto-saved drafts, the lifecycle, the Drafts & Outbox surface, Mail-style dismiss, and cross-launch persistence. Update the Status line to `shipped`.
- [ ] **Step 2: Update `replying.md`** — replace "There is no manual insertion of an optimistic comment" / "Submit then refresh" with the optimistic inline comment, durable retry, and failed-tap actions.
- [ ] **Step 3: Update `new-post.md`** — replace "There is no optimistic local insertion before the server confirms" with the pending post detail + swap-on-success + durable retry.
- [ ] **Step 4: Commit**

```bash
git add docs/features/draft-persistence.md docs/features/replying.md docs/features/new-post.md
git commit -m "docs: update composing features for durable optimistic behavior"
```

---

## Self-Review

**Spec coverage:**
- Instant comment → Tasks 8–11. Instant post → Tasks 13–14. ✓
- Durable drafts (per-target, silent restore, auto-save, cross-launch) → Tasks 1–3, 8–9, 13. ✓
- Self-healing retry (backoff, reachability, launch resume, park-on-permanent) → Tasks 6–7. ✓
- One recovery home → Tasks 16–17. ✓
- Mail-style dismiss → Tasks 9, 14. ✓
- Dedup (non-idempotent hazard) → Tasks 4, 6 (engine pre-check; this is the lower-risk equivalent of the spec's importer heuristic — noted as a deliberate refinement). ✓
- Snapshots → Tasks 12, 15, 16. Migration test → Task 2. Engine tests → Task 6. ✓
- Docs → Task 18. ✓

**Placeholder scan:** Data-layer tasks (1–7) contain complete code. UI tasks (10–17) contain concrete code plus explicit `NOTE for implementer` callouts where exact existing view-internal names must be confirmed against the real files — these are pointers to verbatim-extracted patterns, not deferred work. The verbatim extracts that ground them are in the brainstorming/exploration transcript and the cited files.

**Type consistency:** `OutboundKind`/`OutboundStatus`/`OutboundContentRecord`/`OutboundDraftInput` are defined in Task 1 and used unchanged in 2–17. Write method names (`upsertOutboundDraft`, `markOutboundQueued`, `markOutboundSending`, `markOutboundRetrying`, `markOutboundFailed`, `deleteOutbound`, `dueOutbound`, `allOutbound`, `loadOutboundDraft`, `matchingServerCommentExists`) are consistent across Tasks 3–7. `ComposerOutboxFailure`/`ComposerOutboxSuccess`/`ComposerOutboxServiceType` consistent across 6–7, 14, 17. `saveDraft`/`submitDraft`/`retryComposition`/`discardComposition`/`loadDraft`/`composerFailureEvents`/`composerSuccessEvents` consistent across 7–17.

## Known follow-ups (not blocking)

- Private message composer (`ComposerTarget.privateMessage`) still uses the blocking path; migrate later.
- Residual duplicate risk if a send commits, the response is lost, and no refresh import matches before an auto-retry (documented in spec).
- Importer-level dedup (spec's original heuristic) deferred in favor of the engine pre-check.
