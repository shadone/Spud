# Optimistic Mutation Outbox (vote / save / hide) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make voting, saving, and hiding feel instant by applying the user's mutation to the UI immediately while a durable background queue sends it to the server, retries transient failures, and rolls back only on permanent rejection.

**Architecture:** A new per-account `OutboxService` actor in `SpudDataKit` owns a persisted `pendingOperation` GRDB table. `LemmyService.vote/setSaved/hidePost` (unchanged signatures) delegate to it: enqueue writes the predicted state to GRDB in one transaction (existing `ValueObservation` repaints instantly) and kicks a drain loop. The drain loop sends each operation via an injected `OutboxNetworkPerforming` collaborator, reconciles authoritative state on success, retries transient failures with backoff (+ reachability + foreground triggers), and rolls back permanent failures, emitting a failure event the app renders as a non-blocking toast. A reconciliation guard stops background refresh fetches from clobbering un-synced state.

**Tech Stack:** Swift 6, UIKit, GRDB, Swift actors, `AsyncStream` (no Combine), LemmyKit (`api: LemmyApi`), Swift Testing / XCTest in `SpudDataKitTests`.

## Global Constraints

- SpudDataKit is **Swift 6.0 language mode**, `SWIFT_STRICT_CONCURRENCY = complete`. New types must be `Sendable`; cross-actor values must not race.
- Persistence is **GRDB**; reactive layer is **AsyncSequence / Observation** — do NOT introduce Core Data or Combine.
- New schema goes in a **new migration `v17`** appended to `AppDatabase+Migrations.swift`; never edit existing migration cases.
- Vote DB encoding: `post.voteStatus` / `comment.voteStatus` is `Int64?` — `1` = up, `0` = down, `nil` = none. This is **distinct** from `LikeStatus` (`liked = 1`, `disliked = -1`, `neutral = 0`); encode carefully.
- `LikeStatus.rawValue` equals the score the vote contributes (`+1` / `-1` / `0`).
- No emojis in code, comments, commits. Conventional commit subjects (`feat:`, `test:`, `refactor:`). Small, focused files and commits.
- In `async` tests, `appDatabase.writer.write { }` resolves to GRDB's async overload — it needs `await`.
- Run unit tests with: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -only-testing:SpudDataKitTests -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -skipMacroValidation test`. After adding new source files, run `make project` first (XcodeGen) so they join the target.
- Regenerate the project after adding files: `make project`.

## File Structure

SpudDataKit (framework, all testable):
- `SpudDataKit/Services/Outbox/OutboxOperation.swift` — value types (`OutboxEntityType`, `OutboxKind`, `OutboxDesiredState`, `OutboxOperation`).
- `SpudDataKit/Services/Outbox/OutboxProjection.swift` — pure vote/save/hide projection + encoding math.
- `SpudDataKit/Services/Outbox/OutboxFailureClass.swift` — transient/permanent classification.
- `SpudDataKit/Services/Outbox/OutboxNetworkPerforming.swift` — send protocol + production `LemmyOutboxPerformer`.
- `SpudDataKit/Services/Outbox/OutboxService.swift` — the actor (`OutboxServiceType`, `OutboxFailure`).
- `SpudDataKit/Services/AppDatabase/Records/PendingOperationRecord.swift` — GRDB record.
- `SpudDataKit/Services/AppDatabase/OptimisticWrites.swift` — targeted field writes (`setPostVote`, `setCommentVote`, `setPostSaved`, `setCommentSaved`, `setPostHidden`).
- `SpudDataKit/Services/AppDatabase/PendingOperationWrites.swift` — enqueue/coalesce/due/remove/recordAttempt/rollback.
- `SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift` — add `v17_pendingOperation` (modify).
- `SpudDataKit/Services/AppDatabase/Importers/PostImporter.swift`, `CommentImporter.swift` — reconciliation guard (modify).
- `SpudDataKit/Services/Lemmy/LemmyService.swift` — delegate vote/setSaved/hidePost; vote signed-out gate (modify).
- `SpudDataKit/Services/Account/AccountService.swift`, `AccountScope.swift` — construct/expose outbox (modify).

Spud app target (UI; build + manual verification):
- `Spud/Scenes/Common/Toast/ToastPresenter.swift` — window-level toast (create).
- `Spud/App/...` (SceneDelegate / AppCoordinator) — subscribe to failure events, foreground drain (modify).
- `Spud/Scenes/PostList/PostListViewController.swift`, `Spud/Scenes/PostDetail/Content/PostDetailViewController.swift`, `Spud/Scenes/MediaViewer/MediaViewerViewController.swift`, `Spud/Scenes/Preferences/HiddenAndMuted/HiddenAndMutedViewModel.swift` — simplify call sites (modify).

---

### Task 1: Outbox operation value types

**Files:**
- Create: `SpudDataKit/Services/Outbox/OutboxOperation.swift`
- Test: `SpudDataKitTests/Outbox/OutboxOperationTests.swift`

**Interfaces:**
- Produces:
  - `enum OutboxEntityType: String, Codable, Sendable { case post, comment }`
  - `enum OutboxKind: String, Codable, Sendable { case vote, save, hide }`
  - `enum OutboxDesiredState: Sendable, Equatable { case vote(LikeStatus); case save(Bool); case hide(Bool) }` with `var kind: OutboxKind`, `var encoded: Int64`, and `static func decode(kind: OutboxKind, raw: Int64) -> OutboxDesiredState`
  - `struct OutboxOperation: Sendable, Equatable { let entityType: OutboxEntityType; let entityServerId: Int64; let desiredState: OutboxDesiredState; var kind: OutboxKind { desiredState.kind } }`

- [ ] **Step 1: Write the failing test**

```swift
import LemmyKit
import Testing
@testable import SpudDataKit

struct OutboxOperationTests {
    @Test func voteEncodingRoundTrips() {
        for status in [LikeStatus.liked, .disliked, .neutral] {
            let state = OutboxDesiredState.vote(status)
            #expect(state.kind == .vote)
            let decoded = OutboxDesiredState.decode(kind: .vote, raw: state.encoded)
            #expect(decoded == state)
        }
    }

    @Test func saveAndHideEncodingRoundTrips() {
        for value in [true, false] {
            let save = OutboxDesiredState.save(value)
            #expect(OutboxDesiredState.decode(kind: .save, raw: save.encoded) == save)
            let hide = OutboxDesiredState.hide(value)
            #expect(OutboxDesiredState.decode(kind: .hide, raw: hide.encoded) == hide)
        }
    }

    @Test func operationDerivesKindFromDesiredState() {
        let op = OutboxOperation(entityType: .post, entityServerId: 7, desiredState: .save(true))
        #expect(op.kind == .save)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run the unit-test command above with `-only-testing:SpudDataKitTests/OutboxOperationTests`.
Expected: FAIL to compile ("cannot find 'OutboxDesiredState' in scope").

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation
import LemmyKit

public enum OutboxEntityType: String, Codable, Sendable {
    case post
    case comment
}

public enum OutboxKind: String, Codable, Sendable {
    case vote
    case save
    case hide
}

/// The absolute desired state to send to the server. Idempotent: re-sending the
/// same value is safe, which is what lets the outbox retry freely.
public enum OutboxDesiredState: Sendable, Equatable {
    case vote(LikeStatus)
    case save(Bool)
    case hide(Bool)

    public var kind: OutboxKind {
        switch self {
        case .vote: .vote
        case .save: .save
        case .hide: .hide
        }
    }

    /// Compact integer encoding for the `desiredState` column. `kind` (stored in
    /// its own column) disambiguates decoding.
    public var encoded: Int64 {
        switch self {
        case let .vote(status): Int64(status.rawValue)
        case let .save(value), let .hide(value): value ? 1 : 0
        }
    }

    public static func decode(kind: OutboxKind, raw: Int64) -> OutboxDesiredState {
        switch kind {
        case .vote: .vote(LikeStatus(rawValue: Int32(raw)) ?? .neutral)
        case .save: .save(raw != 0)
        case .hide: .hide(raw != 0)
        }
    }
}

public struct OutboxOperation: Sendable, Equatable {
    public let entityType: OutboxEntityType
    public let entityServerId: Int64
    public let desiredState: OutboxDesiredState

    public var kind: OutboxKind { desiredState.kind }

    public init(entityType: OutboxEntityType, entityServerId: Int64, desiredState: OutboxDesiredState) {
        self.entityType = entityType
        self.entityServerId = entityServerId
        self.desiredState = desiredState
    }
}
```

- [ ] **Step 4: Run `make project`, then run the test to verify it passes**

Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add SpudDataKit/Services/Outbox/OutboxOperation.swift SpudDataKitTests/Outbox/OutboxOperationTests.swift
git commit -m "feat: add outbox operation value types"
```

---

### Task 2: Vote/save/hide projection math

**Files:**
- Create: `SpudDataKit/Services/Outbox/OutboxProjection.swift`
- Test: `SpudDataKitTests/Outbox/OutboxProjectionTests.swift`

**Interfaces:**
- Consumes: `LikeStatus` (LemmyKit), `VoteStatus` (Task 1 not needed; from `SpudDataKit/Utils/VoteStatus.swift`).
- Produces:
  - `enum OutboxProjection`
  - `static func voteStatus(fromDB raw: Int64?) -> VoteStatus` (`1`→`.up`, `0`→`.down`, `nil`→`.neutral`)
  - `static func dbVoteStatus(for status: LikeStatus) -> Int64?` (`.liked`→`1`, `.disliked`→`0`, `.neutral`→`nil`)
  - `static func contribution(_ status: VoteStatus) -> Int64` (`.up`→`1`, `.down`→`-1`, `.neutral`→`0`)
  - `static func voteScoreDelta(currentDB raw: Int64?, desired: LikeStatus) -> Int64` (`desired.rawValue - contribution(current)`)

- [ ] **Step 1: Write the failing test**

```swift
import LemmyKit
import Testing
@testable import SpudDataKit

struct OutboxProjectionTests {
    @Test func dbVoteStatusEncodesDistinctlyFromLikeStatus() {
        #expect(OutboxProjection.dbVoteStatus(for: .liked) == 1)
        #expect(OutboxProjection.dbVoteStatus(for: .disliked) == 0)   // NOT -1
        #expect(OutboxProjection.dbVoteStatus(for: .neutral) == nil)
    }

    @Test func scoreDeltaCoversAllTransitions() {
        // (currentDB, desired) -> expected score delta
        #expect(OutboxProjection.voteScoreDelta(currentDB: nil, desired: .liked) == 1)     // neutral -> up
        #expect(OutboxProjection.voteScoreDelta(currentDB: nil, desired: .disliked) == -1) // neutral -> down
        #expect(OutboxProjection.voteScoreDelta(currentDB: 1, desired: .neutral) == -1)    // up -> neutral
        #expect(OutboxProjection.voteScoreDelta(currentDB: 0, desired: .neutral) == 1)     // down -> neutral
        #expect(OutboxProjection.voteScoreDelta(currentDB: 1, desired: .disliked) == -2)   // up -> down
        #expect(OutboxProjection.voteScoreDelta(currentDB: 0, desired: .liked) == 2)       // down -> up
        #expect(OutboxProjection.voteScoreDelta(currentDB: 1, desired: .liked) == 0)       // idempotent
    }

    @Test func voteStatusDecodesFromDB() {
        #expect(OutboxProjection.voteStatus(fromDB: 1).isUp)
        #expect(OutboxProjection.voteStatus(fromDB: 0).isDown)
        if case .neutral = OutboxProjection.voteStatus(fromDB: nil) {} else { Issue.record("expected neutral") }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

`-only-testing:SpudDataKitTests/OutboxProjectionTests` — Expected: FAIL to compile.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation
import LemmyKit

/// Pure math translating a desired absolute vote into the local DB field
/// changes the optimistic UI needs. Save/hide are direct boolean writes and do
/// not need a projection helper.
public enum OutboxProjection {
    public static func voteStatus(fromDB raw: Int64?) -> VoteStatus {
        switch raw {
        case 1: .up
        case 0: .down
        default: .neutral
        }
    }

    public static func dbVoteStatus(for status: LikeStatus) -> Int64? {
        switch status {
        case .liked: 1
        case .disliked: 0
        case .neutral: nil
        }
    }

    public static func contribution(_ status: VoteStatus) -> Int64 {
        switch status {
        case .up: 1
        case .down: -1
        case .neutral: 0
        }
    }

    /// Score change when moving from the current DB vote to `desired`.
    /// `LikeStatus.rawValue` already equals the contribution of the target vote.
    public static func voteScoreDelta(currentDB raw: Int64?, desired: LikeStatus) -> Int64 {
        Int64(desired.rawValue) - contribution(voteStatus(fromDB: raw))
    }
}
```

- [ ] **Step 4: Run the test to verify it passes** — Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add SpudDataKit/Services/Outbox/OutboxProjection.swift SpudDataKitTests/Outbox/OutboxProjectionTests.swift
git commit -m "feat: add outbox vote projection math"
```

---

### Task 3: pendingOperation table + record (migration v17)

**Files:**
- Create: `SpudDataKit/Services/AppDatabase/Records/PendingOperationRecord.swift`
- Modify: `SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift` (append `v17_pendingOperation` before `return migrator`)
- Test: `SpudDataKitTests/Outbox/PendingOperationRecordTests.swift`

**Interfaces:**
- Produces: `struct PendingOperationRecord: Codable, FetchableRecord, MutablePersistableRecord, Sendable, Equatable` with stored columns:
  `id: Int64?`, `accountId: Int64`, `entityType: String`, `entityServerId: Int64`, `kind: String`, `desiredState: Int64`, `baseline: Int64?`, `attempts: Int64`, `lastError: String?`, `nextAttemptAt: Double?`, `createdAt: Double`, `updatedAt: Double`. `static let databaseTableName = "pendingOperation"`; `mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }`.

Notes on the `baseline` column: a single nullable `Int64` (refines the spec's JSON payload — the only kind-specific datum is one nullable int). For vote it stores the prior DB `voteStatus` (`1`/`0`/`nil`); for save/hide it stores the prior bool as `1`/`0`.

- [ ] **Step 1: Write the failing test**

```swift
import GRDB
import Testing
@testable import SpudDataKit

struct PendingOperationRecordTests {
    @Test func tableExistsAndRecordRoundTrips() async throws {
        let appDatabase = try AppDatabase.inMemory()
        var record = PendingOperationRecord(
            accountId: 1, entityType: "post", entityServerId: 42, kind: "vote",
            desiredState: 1, baseline: nil, attempts: 0, lastError: nil,
            nextAttemptAt: nil, createdAt: 100, updatedAt: 100
        )
        try await appDatabase.writer.write { db in try record.insert(db) }
        let fetched = try await appDatabase.writer.read { db in
            try PendingOperationRecord.fetchOne(db)
        }
        #expect(fetched?.entityServerId == 42)
        #expect(fetched?.kind == "vote")
    }

    @Test func uniqueConstraintCoalescesPerKindPerTarget() async throws {
        let appDatabase = try AppDatabase.inMemory()
        func make(kind: String) -> PendingOperationRecord {
            PendingOperationRecord(accountId: 1, entityType: "post", entityServerId: 42,
                kind: kind, desiredState: 1, baseline: nil, attempts: 0, lastError: nil,
                nextAttemptAt: nil, createdAt: 1, updatedAt: 1)
        }
        try await appDatabase.writer.write { db in
            var v = make(kind: "vote"); try v.insert(db)
            var s = make(kind: "save"); try s.insert(db)   // different kind, same target: allowed
        }
        // Same (account, entity, kind) twice must violate UNIQUE.
        await #expect(throws: (any Error).self) {
            try await appDatabase.writer.write { db in
                var dup = make(kind: "vote"); try dup.insert(db)
            }
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails** — Expected: FAIL (no such table / type).

- [ ] **Step 3a: Add the migration** (in `AppDatabase+Migrations.swift`, immediately before `return migrator`)

```swift
migrator.registerMigration("v17_pendingOperation") { db in
    try db.create(table: "pendingOperation") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("accountId", .integer)
            .notNull()
            .indexed()
            .references("account", onDelete: .cascade)
        t.column("entityType", .text).notNull()
        t.column("entityServerId", .integer).notNull()
        t.column("kind", .text).notNull()
        t.column("desiredState", .integer).notNull()
        t.column("baseline", .integer)
        t.column("attempts", .integer).notNull().defaults(to: 0)
        t.column("lastError", .text)
        t.column("nextAttemptAt", .double)
        t.column("createdAt", .double).notNull()
        t.column("updatedAt", .double).notNull()
        t.uniqueKey(["accountId", "entityType", "entityServerId", "kind"])
    }
}
```

(Confirm the accounts table name is `account` — match the `.references` used by existing migrations such as `v16_siteAdmin`'s `site` reference.)

- [ ] **Step 3b: Add the record**

```swift
import Foundation
import GRDB

/// A persisted, not-yet-synced idempotent set-state mutation (vote/save/hide).
/// Coalesced per `(accountId, entityType, entityServerId, kind)` by a unique key.
public struct PendingOperationRecord: Codable, FetchableRecord, MutablePersistableRecord, Sendable, Equatable {
    public var id: Int64?
    public var accountId: Int64
    public var entityType: String
    public var entityServerId: Int64
    public var kind: String
    public var desiredState: Int64
    /// Prior local state to roll back to: vote `voteStatus` (1/0/nil) or save/hide bool (1/0).
    public var baseline: Int64?
    public var attempts: Int64
    public var lastError: String?
    public var nextAttemptAt: Double?
    public var createdAt: Double
    public var updatedAt: Double

    public static let databaseTableName = "pendingOperation"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
```

- [ ] **Step 4: Run `make project`, then run the test to verify it passes** — Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add SpudDataKit/Services/AppDatabase/Records/PendingOperationRecord.swift SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift SpudDataKitTests/Outbox/PendingOperationRecordTests.swift
git commit -m "feat: add pendingOperation table and record (migration v17)"
```

---

### Task 4: Targeted optimistic field writes

**Files:**
- Create: `SpudDataKit/Services/AppDatabase/OptimisticWrites.swift`
- Test: `SpudDataKitTests/Outbox/OptimisticWritesTests.swift`

**Interfaces:**
- Consumes: `AppDatabase`, GRDB `Database`.
- Produces (static, transaction-internal so Task 5 can compose them inside one write):
  - `static func setPostVote(_ db: Database, accountId: Int64, serverPostId: Int64, voteStatus: Int64?, scoreDelta: Int64) throws`
  - `static func setCommentVote(_ db: Database, accountId: Int64, serverCommentId: Int64, voteStatus: Int64?, scoreDelta: Int64) throws`
  - `static func setPostSaved(_ db: Database, accountId: Int64, serverPostId: Int64, isSaved: Bool) throws`
  - `static func setCommentSaved(_ db: Database, accountId: Int64, serverCommentId: Int64, isSaved: Bool) throws`
  - `static func setPostHidden(_ db: Database, accountId: Int64, serverPostId: Int64, isHidden: Bool) throws`
  - All grouped under `enum OptimisticWrites`.

Implementation note: copy the row-keying (which columns identify a post/comment for this account) from the existing `setPostIsHidden` in `Importers/PostImporter.swift` and from `postVoteStatus`/`commentVoteStatus` in `LemmyServiceQueries.swift`. The post id column is `postId`; verify the comment id column name (likely `localCommentId`) and whether `post`/`comment` rows carry `accountId` directly or are joined — match the existing WHERE clauses exactly. Use raw SQL `UPDATE` with `score = score + ?` for the delta so concurrent reads stay consistent.

- [ ] **Step 1: Write the failing test**

```swift
import GRDB
import Testing
@testable import SpudDataKit

struct OptimisticWritesTests {
    // Helper: insert a minimal post row for (accountId, serverPostId) with a known
    // score/voteStatus/isSaved/isHidden. Mirror the columns PostRecord requires;
    // reuse a fixture factory if SpudDataKitTests already has one.
    @Test func setPostVoteAppliesDeltaAndStatus() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, serverPostId) = try await seedPost(appDatabase, score: 10, voteStatus: nil)

        try await appDatabase.writer.write { db in
            try OptimisticWrites.setPostVote(db, accountId: accountId, serverPostId: serverPostId,
                                             voteStatus: 1, scoreDelta: 1)
        }

        let (score, vote) = try await readPostVote(appDatabase, accountId: accountId, serverPostId: serverPostId)
        #expect(score == 11)
        #expect(vote == 1)
    }

    @Test func setPostSavedTogglesFlag() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, serverPostId) = try await seedPost(appDatabase, score: 0, voteStatus: nil)
        try await appDatabase.writer.write { db in
            try OptimisticWrites.setPostSaved(db, accountId: accountId, serverPostId: serverPostId, isSaved: true)
        }
        let saved = try await readPostSaved(appDatabase, accountId: accountId, serverPostId: serverPostId)
        #expect(saved == true)
    }
}
```

(Write the `seedPost` / `readPostVote` / `readPostSaved` helpers in the test file. If `SpudDataKitTests` already has a post fixture, reuse it; otherwise insert the minimal required `PostRecord` columns directly. Mirror the `OutboxProjectionTests` style.)

- [ ] **Step 2: Run test to verify it fails** — Expected: FAIL to compile.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation
import GRDB

/// Targeted single-field writes used by the outbox to apply (and roll back)
/// optimistic state without re-importing a whole entity. Each runs inside a
/// caller-provided transaction so enqueue can keep the projection and the
/// pending-row upsert atomic.
public enum OptimisticWrites {
    public static func setPostVote(_ db: Database, accountId: Int64, serverPostId: Int64,
                                   voteStatus: Int64?, scoreDelta: Int64) throws {
        try db.execute(sql: """
            UPDATE post SET voteStatus = ?, score = score + ?
            WHERE postId = ? AND accountId = ?
            """, arguments: [voteStatus, scoreDelta, serverPostId, accountId])
    }

    public static func setCommentVote(_ db: Database, accountId: Int64, serverCommentId: Int64,
                                      voteStatus: Int64?, scoreDelta: Int64) throws {
        try db.execute(sql: """
            UPDATE comment SET voteStatus = ?, score = score + ?
            WHERE localCommentId = ? AND accountId = ?
            """, arguments: [voteStatus, scoreDelta, serverCommentId, accountId])
    }

    public static func setPostSaved(_ db: Database, accountId: Int64, serverPostId: Int64, isSaved: Bool) throws {
        try db.execute(sql: "UPDATE post SET isSaved = ? WHERE postId = ? AND accountId = ?",
                       arguments: [isSaved, serverPostId, accountId])
    }

    public static func setCommentSaved(_ db: Database, accountId: Int64, serverCommentId: Int64, isSaved: Bool) throws {
        try db.execute(sql: "UPDATE comment SET isSaved = ? WHERE localCommentId = ? AND accountId = ?",
                       arguments: [isSaved, serverCommentId, accountId])
    }

    public static func setPostHidden(_ db: Database, accountId: Int64, serverPostId: Int64, isHidden: Bool) throws {
        try db.execute(sql: "UPDATE post SET isHidden = ? WHERE postId = ? AND accountId = ?",
                       arguments: [isHidden, serverPostId, accountId])
    }
}
```

(Adjust table/column names — `postId`, `localCommentId`, `accountId` — to match the actual schema if they differ. Verify against `PostRecord`/`CommentRecord` and `LemmyServiceQueries.swift`.)

- [ ] **Step 4: Run the test to verify it passes** — Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add SpudDataKit/Services/AppDatabase/OptimisticWrites.swift SpudDataKitTests/Outbox/OptimisticWritesTests.swift
git commit -m "feat: add targeted optimistic field writes for vote/save/hide"
```

---

### Task 5: Pending-operation queue writes (enqueue/coalesce/due/rollback)

**Files:**
- Create: `SpudDataKit/Services/AppDatabase/PendingOperationWrites.swift`
- Test: `SpudDataKitTests/Outbox/PendingOperationWritesTests.swift`

**Interfaces:**
- Consumes: `OutboxOperation`, `OutboxDesiredState`, `OutboxProjection`, `OptimisticWrites`, `PendingOperationRecord`.
- Produces (extension methods on `AppDatabase`, all `async throws`):
  - `func enqueueOutboxOperation(_ op: OutboxOperation, accountId: Int64, now: Double)` — one write transaction: capture baseline if no existing row; if `desiredState` equals baseline, revert projection + delete row (toggle-to-baseline); else apply projection (Task 4) and upsert the row (coalesce: update `desiredState`/`attempts=0`/`lastError=nil`/`nextAttemptAt=now`/`updatedAt`, preserve `baseline`/`createdAt`).
  - `func dueOutboxOperations(accountId: Int64, asOf now: Double) async throws -> [PendingOperationRecord]` — `nextAttemptAt IS NULL OR nextAttemptAt <= now`, ordered `createdAt` asc.
  - `func allOutboxOperations(accountId: Int64) async throws -> [PendingOperationRecord]`
  - `func removeOutboxOperation(id: Int64) async throws`
  - `func recordOutboxAttempt(id: Int64, lastError: String, nextAttemptAt: Double) async throws` — increments `attempts`.
  - `func rollbackOutboxOperation(_ record: PendingOperationRecord) async throws` — one transaction: apply inverse projection to restore baseline, then delete the row.

Baseline / inverse semantics:
- Vote baseline = prior `voteStatus` (1/0/nil). Net applied score delta since baseline = `desired.rawValue - contribution(voteStatus(fromDB: baseline))`. Rollback sets `voteStatus = baseline`, `score += -(netDelta)`.
- Save/hide baseline = prior bool (1/0). Rollback restores it.
- "desiredState equals baseline" for vote: `OutboxProjection.dbVoteStatus(for: status) == baseline`. For save/hide: `(value ? 1 : 0) == baseline`.

- [ ] **Step 1: Write the failing tests**

```swift
import GRDB
import LemmyKit
import Testing
@testable import SpudDataKit

struct PendingOperationWritesTests {
    @Test func enqueueAppliesOptimisticWriteAndCreatesRow() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, postId) = try await seedPost(appDatabase, score: 5, voteStatus: nil)

        try await appDatabase.enqueueOutboxOperation(
            OutboxOperation(entityType: .post, entityServerId: postId, desiredState: .vote(.liked)),
            accountId: accountId, now: 100)

        let (score, vote) = try await readPostVote(appDatabase, accountId: accountId, serverPostId: postId)
        #expect(score == 6)
        #expect(vote == 1)
        let rows = try await appDatabase.allOutboxOperations(accountId: accountId)
        #expect(rows.count == 1)
        #expect(rows[0].baseline == nil)          // baseline neutral captured
        #expect(rows[0].desiredState == 1)         // LikeStatus.liked
    }

    @Test func secondVoteCoalescesIntoOneRowPreservingBaseline() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, postId) = try await seedPost(appDatabase, score: 5, voteStatus: nil)
        func enqueue(_ s: LikeStatus, at t: Double) async throws {
            try await appDatabase.enqueueOutboxOperation(
                OutboxOperation(entityType: .post, entityServerId: postId, desiredState: .vote(s)),
                accountId: accountId, now: t)
        }
        try await enqueue(.liked, at: 100)   // neutral -> up: score 6
        try await enqueue(.disliked, at: 200) // up -> down: score 4
        let rows = try await appDatabase.allOutboxOperations(accountId: accountId)
        #expect(rows.count == 1)
        #expect(rows[0].baseline == nil)       // still the original neutral baseline
        let (score, vote) = try await readPostVote(appDatabase, accountId: accountId, serverPostId: postId)
        #expect(score == 4)
        #expect(vote == 0)
    }

    @Test func toggleBackToBaselineDeletesRowAndReverts() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, postId) = try await seedPost(appDatabase, score: 5, voteStatus: nil)
        try await appDatabase.enqueueOutboxOperation(
            .init(entityType: .post, entityServerId: postId, desiredState: .vote(.liked)),
            accountId: accountId, now: 100)
        try await appDatabase.enqueueOutboxOperation(
            .init(entityType: .post, entityServerId: postId, desiredState: .vote(.neutral)),
            accountId: accountId, now: 200)
        let rows = try await appDatabase.allOutboxOperations(accountId: accountId)
        #expect(rows.isEmpty)
        let (score, vote) = try await readPostVote(appDatabase, accountId: accountId, serverPostId: postId)
        #expect(score == 5)
        #expect(vote == nil)
    }

    @Test func rollbackRestoresBaseline() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, postId) = try await seedPost(appDatabase, score: 5, voteStatus: nil)
        try await appDatabase.enqueueOutboxOperation(
            .init(entityType: .post, entityServerId: postId, desiredState: .vote(.liked)),
            accountId: accountId, now: 100)
        let row = try #require(try await appDatabase.allOutboxOperations(accountId: accountId).first)
        try await appDatabase.rollbackOutboxOperation(row)
        let (score, vote) = try await readPostVote(appDatabase, accountId: accountId, serverPostId: postId)
        #expect(score == 5)
        #expect(vote == nil)
        #expect(try await appDatabase.allOutboxOperations(accountId: accountId).isEmpty)
    }

    @Test func dueFiltersByNextAttempt() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, postId) = try await seedPost(appDatabase, score: 0, voteStatus: nil)
        try await appDatabase.enqueueOutboxOperation(
            .init(entityType: .post, entityServerId: postId, desiredState: .vote(.liked)),
            accountId: accountId, now: 100)
        let row = try #require(try await appDatabase.allOutboxOperations(accountId: accountId).first)
        try await appDatabase.recordOutboxAttempt(id: row.id!, lastError: "boom", nextAttemptAt: 500)
        #expect(try await appDatabase.dueOutboxOperations(accountId: accountId, asOf: 400).isEmpty)
        #expect(try await appDatabase.dueOutboxOperations(accountId: accountId, asOf: 600).count == 1)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail** — Expected: FAIL to compile.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation
import GRDB
import LemmyKit

public extension AppDatabase {
    func enqueueOutboxOperation(_ op: OutboxOperation, accountId: Int64, now: Double) async throws {
        try await writer.write { db in
            let existing = try Self.fetchPending(db, accountId: accountId, op: op)
            let baseline = try existing?.baseline ?? Self.currentBaseline(db, accountId: accountId, op: op)

            // Toggle-to-baseline: nothing to sync, revert projection and drop the row.
            if Self.desiredEqualsBaseline(op.desiredState, baseline: baseline) {
                try Self.applyProjection(db, accountId: accountId, op: op, toBaseline: baseline)
                if let id = existing?.id { try Self.deletePending(db, id: id) }
                return
            }

            try Self.applyProjection(db, accountId: accountId, op: op, toBaseline: nil)

            if var row = existing {
                row.desiredState = op.desiredState.encoded
                row.attempts = 0
                row.lastError = nil
                row.nextAttemptAt = now
                row.updatedAt = now
                try row.update(db)
            } else {
                var row = PendingOperationRecord(
                    accountId: accountId, entityType: op.entityType.rawValue,
                    entityServerId: op.entityServerId, kind: op.kind.rawValue,
                    desiredState: op.desiredState.encoded, baseline: baseline,
                    attempts: 0, lastError: nil, nextAttemptAt: now,
                    createdAt: now, updatedAt: now)
                try row.insert(db)
            }
        }
    }

    func dueOutboxOperations(accountId: Int64, asOf now: Double) async throws -> [PendingOperationRecord] {
        try await writer.read { db in
            try PendingOperationRecord
                .filter(Column("accountId") == accountId)
                .filter(Column("nextAttemptAt") == nil || Column("nextAttemptAt") <= now)
                .order(Column("createdAt").asc)
                .fetchAll(db)
        }
    }

    func allOutboxOperations(accountId: Int64) async throws -> [PendingOperationRecord] {
        try await writer.read { db in
            try PendingOperationRecord
                .filter(Column("accountId") == accountId)
                .order(Column("createdAt").asc)
                .fetchAll(db)
        }
    }

    func removeOutboxOperation(id: Int64) async throws {
        _ = try await writer.write { db in try Self.deletePending(db, id: id) }
    }

    func recordOutboxAttempt(id: Int64, lastError: String, nextAttemptAt: Double) async throws {
        try await writer.write { db in
            try db.execute(sql: """
                UPDATE pendingOperation SET attempts = attempts + 1, lastError = ?, nextAttemptAt = ?
                WHERE id = ?
                """, arguments: [lastError, nextAttemptAt, id])
        }
    }

    func rollbackOutboxOperation(_ record: PendingOperationRecord) async throws {
        try await writer.write { db in
            try Self.applyRollback(db, record: record)
            if let id = record.id { try Self.deletePending(db, id: id) }
        }
    }
}

private extension AppDatabase {
    static func fetchPending(_ db: Database, accountId: Int64, op: OutboxOperation) throws -> PendingOperationRecord? {
        try PendingOperationRecord
            .filter(Column("accountId") == accountId)
            .filter(Column("entityType") == op.entityType.rawValue)
            .filter(Column("entityServerId") == op.entityServerId)
            .filter(Column("kind") == op.kind.rawValue)
            .fetchOne(db)
    }

    static func deletePending(_ db: Database, id: Int64) throws {
        _ = try PendingOperationRecord.deleteOne(db, key: id)
    }

    /// Read the current local state to snapshot as the rollback baseline.
    static func currentBaseline(_ db: Database, accountId: Int64, op: OutboxOperation) throws -> Int64? {
        switch op.desiredState {
        case .vote:
            let column = op.entityType == .post ? "post" : "comment"
            let idColumn = op.entityType == .post ? "postId" : "localCommentId"
            return try Int64.fetchOne(db, sql:
                "SELECT voteStatus FROM \(column) WHERE \(idColumn) = ? AND accountId = ?",
                arguments: [op.entityServerId, accountId])
        case .save:
            let column = op.entityType == .post ? "post" : "comment"
            let idColumn = op.entityType == .post ? "postId" : "localCommentId"
            let saved = try Bool.fetchOne(db, sql:
                "SELECT isSaved FROM \(column) WHERE \(idColumn) = ? AND accountId = ?",
                arguments: [op.entityServerId, accountId]) ?? false
            return saved ? 1 : 0
        case .hide:
            let hidden = try Bool.fetchOne(db, sql:
                "SELECT isHidden FROM post WHERE postId = ? AND accountId = ?",
                arguments: [op.entityServerId, accountId]) ?? false
            return hidden ? 1 : 0
        }
    }

    static func desiredEqualsBaseline(_ desired: OutboxDesiredState, baseline: Int64?) -> Bool {
        switch desired {
        case let .vote(status): OutboxProjection.dbVoteStatus(for: status) == baseline
        case let .save(value), let .hide(value): (value ? 1 : 0) == baseline
        }
    }

    /// Apply the optimistic projection for `op.desiredState`. When `toBaseline`
    /// is non-nil this is a revert (compute delta from current to baseline).
    static func applyProjection(_ db: Database, accountId: Int64, op: OutboxOperation, toBaseline baseline: Int64?) throws {
        switch op.desiredState {
        case let .vote(status):
            let target: LikeStatus = baseline == nil && toBaselineRequested(baseline)
                ? .neutral : status
            // For a forward apply, target = status. For a revert, decode baseline.
            let effective: LikeStatus = baseline.flatMap(Self.likeStatus(fromBaseline:)) ?? status
            let chosen = isRevert(baseline) ? effective : status
            _ = target // keep compiler happy if unused in your final form
            let currentDB = try currentVoteDB(db, accountId: accountId, op: op)
            let delta = OutboxProjection.voteScoreDelta(currentDB: currentDB, desired: chosen)
            if op.entityType == .post {
                try OptimisticWrites.setPostVote(db, accountId: accountId, serverPostId: op.entityServerId,
                    voteStatus: OutboxProjection.dbVoteStatus(for: chosen), scoreDelta: delta)
            } else {
                try OptimisticWrites.setCommentVote(db, accountId: accountId, serverCommentId: op.entityServerId,
                    voteStatus: OutboxProjection.dbVoteStatus(for: chosen), scoreDelta: delta)
            }
        case let .save(value):
            let chosen = isRevert(baseline) ? (baseline == 1) : value
            if op.entityType == .post {
                try OptimisticWrites.setPostSaved(db, accountId: accountId, serverPostId: op.entityServerId, isSaved: chosen)
            } else {
                try OptimisticWrites.setCommentSaved(db, accountId: accountId, serverCommentId: op.entityServerId, isSaved: chosen)
            }
        case let .hide(value):
            let chosen = isRevert(baseline) ? (baseline == 1) : value
            try OptimisticWrites.setPostHidden(db, accountId: accountId, serverPostId: op.entityServerId, isHidden: chosen)
        }
    }

    static func applyRollback(_ db: Database, record: PendingOperationRecord) throws {
        let kind = OutboxKind(rawValue: record.kind) ?? .vote
        let entityType = OutboxEntityType(rawValue: record.entityType) ?? .post
        switch kind {
        case .vote:
            let baselineVote = record.baseline
            let currentDB = try currentVoteDB(db, accountId: record.accountId,
                op: OutboxOperation(entityType: entityType, entityServerId: record.entityServerId, desiredState: .vote(.neutral)))
            // Move current -> baseline.
            let baselineStatus = likeStatus(fromBaseline: baselineVote) ?? .neutral
            let delta = OutboxProjection.voteScoreDelta(currentDB: currentDB, desired: baselineStatus)
            if entityType == .post {
                try OptimisticWrites.setPostVote(db, accountId: record.accountId, serverPostId: record.entityServerId,
                    voteStatus: baselineVote, scoreDelta: delta)
            } else {
                try OptimisticWrites.setCommentVote(db, accountId: record.accountId, serverCommentId: record.entityServerId,
                    voteStatus: baselineVote, scoreDelta: delta)
            }
        case .save:
            let saved = record.baseline == 1
            if entityType == .post {
                try OptimisticWrites.setPostSaved(db, accountId: record.accountId, serverPostId: record.entityServerId, isSaved: saved)
            } else {
                try OptimisticWrites.setCommentSaved(db, accountId: record.accountId, serverCommentId: record.entityServerId, isSaved: saved)
            }
        case .hide:
            try OptimisticWrites.setPostHidden(db, accountId: record.accountId, serverPostId: record.entityServerId, isHidden: record.baseline == 1)
        }
    }

    // Helpers.
    static func isRevert(_ baseline: Int64?) -> Bool { false } // forward apply path; revert handled in applyRollback
    static func toBaselineRequested(_ baseline: Int64?) -> Bool { false }
    static func likeStatus(fromBaseline raw: Int64?) -> LikeStatus? {
        switch raw { case 1: .liked; case 0: .disliked; case nil: LikeStatus.neutral; default: nil }
    }
    static func currentVoteDB(_ db: Database, accountId: Int64, op: OutboxOperation) throws -> Int64? {
        let column = op.entityType == .post ? "post" : "comment"
        let idColumn = op.entityType == .post ? "postId" : "localCommentId"
        return try Int64.fetchOne(db, sql:
            "SELECT voteStatus FROM \(column) WHERE \(idColumn) = ? AND accountId = ?",
            arguments: [op.entityServerId, accountId])
    }
}
```

> Implementer note: the `applyProjection` revert branch above is over-elaborated — simplify it. The clean shape is: `enqueueOutboxOperation` forward-applies `op.desiredState` directly (no revert logic), and the toggle-to-baseline case instead calls `applyRollback`-style logic to move current → baseline, then deletes the row. Refactor so `applyProjection` only does the forward apply and a single `moveVote(db, to: LikeStatus)` helper is shared by toggle-to-baseline and `applyRollback`. Keep the tests from Step 1 green as the contract.

- [ ] **Step 4: Run the tests to verify they pass** — Expected: PASS (5 tests). Refactor per the note while keeping them green.

- [ ] **Step 5: Commit**

```bash
git add SpudDataKit/Services/AppDatabase/PendingOperationWrites.swift SpudDataKitTests/Outbox/PendingOperationWritesTests.swift
git commit -m "feat: add outbox queue writes (enqueue, coalesce, due, rollback)"
```

---

### Task 6: Transient/permanent failure classification

**Files:**
- Create: `SpudDataKit/Services/Outbox/OutboxFailureClass.swift`
- Test: `SpudDataKitTests/Outbox/OutboxFailureClassTests.swift`

**Interfaces:**
- Consumes: `LemmyServiceError`, `LemmyApiError` (LemmyKit), `URLError`.
- Produces:
  - `enum OutboxFailureClass: Sendable, Equatable { case transient; case permanent }`
  - `static func classify(_ error: Error, isOnline: Bool) -> OutboxFailureClass`

Policy (errs toward retrying — a vote should not be dropped on ambiguity):
- `!isOnline` → `.transient`.
- `LemmyServiceError.requiresAuthentication` → `.permanent`.
- `LemmyApiError.unauthorized` → `.permanent`.
- `LemmyApiError.failedToDeserializeResponse` → `.permanent` (don't spin forever on a parse bug).
- `URLError` (any) → `.transient`.
- `LemmyApiError.network`, `.serverError`, `.unknownServerError`, `.unknown` → `.transient` (refine `.unknownServerError`/`.unknown` to `.permanent` only when a carried HTTP status is a non-auth 4xx — verify the associated values on `LemmyApiError`).
- default → `.transient`.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import LemmyKit
import Testing
@testable import SpudDataKit

struct OutboxFailureClassTests {
    @Test func offlineIsTransient() {
        #expect(OutboxFailureClass.classify(LemmyServiceError.requiresAuthentication, isOnline: false) == .transient)
    }
    @Test func requiresAuthOnlineIsPermanent() {
        #expect(OutboxFailureClass.classify(LemmyServiceError.requiresAuthentication, isOnline: true) == .permanent)
    }
    @Test func timeoutIsTransient() {
        #expect(OutboxFailureClass.classify(URLError(.timedOut), isOnline: true) == .transient)
    }
    @Test func unauthorizedApiErrorIsPermanent() {
        #expect(OutboxFailureClass.classify(LemmyApiError.unauthorized, isOnline: true) == .permanent)
    }
}
```

- [ ] **Step 2: Run test to verify it fails** — Expected: FAIL to compile.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation
import LemmyKit

/// Decides whether a failed outbox send should be retried forever (transient)
/// or rolled back and surfaced (permanent). Distinct from `LoadFailure`, which
/// collapses auth into `.unreachable`; the outbox must treat auth as permanent.
public enum OutboxFailureClass: Sendable, Equatable {
    case transient
    case permanent

    public static func classify(_ error: Error, isOnline: Bool) -> OutboxFailureClass {
        if !isOnline { return .transient }

        switch error {
        case LemmyServiceError.requiresAuthentication:
            return .permanent
        case is URLError:
            return .transient
        case let apiError as LemmyApiError:
            return classify(apiError)
        default:
            return .transient
        }
    }

    private static func classify(_ apiError: LemmyApiError) -> OutboxFailureClass {
        switch apiError {
        case .unauthorized, .failedToDeserializeResponse:
            return .permanent
        case .network, .serverError, .unknownServerError, .unknown:
            return .transient
        @unknown default:
            return .transient
        }
    }
}
```

(If `LemmyApiError`'s case set differs, align the switch with its actual cases — confirm against `LoadFailure.kind(forApiError:)` which already enumerates them. Refine `.unknownServerError(statusCode, _)` to `.permanent` for non-auth 4xx if the status is available.)

- [ ] **Step 4: Run the test to verify it passes** — Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add SpudDataKit/Services/Outbox/OutboxFailureClass.swift SpudDataKitTests/Outbox/OutboxFailureClassTests.swift
git commit -m "feat: add outbox transient/permanent error classification"
```

---

### Task 7: Reconciliation guard in importers

**Files:**
- Modify: `SpudDataKit/Services/AppDatabase/Importers/PostImporter.swift`, `CommentImporter.swift`
- Test: `SpudDataKitTests/Outbox/ReconciliationGuardTests.swift`

**Interfaces:**
- Modify the upsert entry points to accept `respectsPendingOutbox: Bool = true`. When `true`, before writing the vote/save/hide fields for an entity, look up `pendingOperation` rows for `(accountId, entityType, entityServerId)` and **preserve** the existing local value for each pending kind:
  - vote pending → keep existing `voteStatus`, `score`, `numberOfUpvotes`, `numberOfDownvotes`
  - save pending → keep existing `isSaved`
  - hide pending → keep existing `isHidden`
- Produces (for Task 8's performer to call the authoritative, unguarded path): `upsertPost(from:accountId:siteId:respectsPendingOutbox:)` and `upsertComment(from:accountId:siteId:respectsPendingOutbox:)` with the flag defaulting to `true`.

Implementation approach: the simplest correct form is to fetch the set of pending `(kind)` for the entity once at the top of the per-entity upsert; if a kind is pending and `respectsPendingOutbox`, read the current row's field(s) for that kind and assign them onto the record before saving (so the incoming server values for those fields are discarded). Keep this isolated in a small private helper, e.g. `preservePendingFields(_ record: inout PostRecord, db:, accountId:)`.

- [ ] **Step 1: Write the failing test**

```swift
import LemmyKit
import Testing
@testable import SpudDataKit

struct ReconciliationGuardTests {
    @Test func refreshDoesNotClobberPendingVote() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId, postId) = try await seedPostWithSite(appDatabase, score: 5, voteStatus: nil)

        // User upvotes optimistically; a pending row now exists.
        try await appDatabase.enqueueOutboxOperation(
            .init(entityType: .post, entityServerId: postId, desiredState: .vote(.liked)),
            accountId: accountId, now: 100)

        // A background refresh returns the still-unvoted server view.
        let staleView = makePostView(postId: postId, myVote: 0, score: 5) // helper builds Components.Schemas.PostView
        try await appDatabase.upsertPost(from: staleView, accountId: accountId, siteId: siteId) // respectsPendingOutbox defaults true

        let (score, vote) = try await readPostVote(appDatabase, accountId: accountId, serverPostId: postId)
        #expect(score == 6)     // optimistic value preserved
        #expect(vote == 1)
    }

    @Test func outboxReconcileWritesServerTruth() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId, postId) = try await seedPostWithSite(appDatabase, score: 5, voteStatus: nil)
        try await appDatabase.enqueueOutboxOperation(
            .init(entityType: .post, entityServerId: postId, desiredState: .vote(.liked)),
            accountId: accountId, now: 100)

        // Authoritative reconcile bypasses the guard.
        let serverView = makePostView(postId: postId, myVote: 1, score: 99)
        try await appDatabase.upsertPost(from: serverView, accountId: accountId, siteId: siteId, respectsPendingOutbox: false)

        let (score, vote) = try await readPostVote(appDatabase, accountId: accountId, serverPostId: postId)
        #expect(score == 99)
        #expect(vote == 1)
    }
}
```

(Reuse or add `seedPostWithSite` and `makePostView` helpers. `makePostView` builds a `Components.Schemas.PostView` fixture — reuse the existing test fixture factory in `SpudDataKitTests` that other importer tests use.)

- [ ] **Step 2: Run tests to verify they fail** — Expected: FAIL (compile: new param) or assertion (guard not applied).

- [ ] **Step 3: Implement the guard** — add the `respectsPendingOutbox` parameter and the `preservePendingFields` helper to `PostImporter`/`CommentImporter`. Show the actual edit in your implementation, threading the flag from `upsertPost`/`upsertComment` into the record-building path. Default `true`. The `mirrorPostInfoToAppDatabase`/`mirrorCommentToAppDatabase` callers keep the default for now (Task 8 changes the reconcile call to pass `false`).

- [ ] **Step 4: Run the tests to verify they pass** — Expected: PASS (2 tests). Also re-run the full `SpudDataKitTests` suite to confirm no existing importer test regressed from the new parameter.

- [ ] **Step 5: Commit**

```bash
git add SpudDataKit/Services/AppDatabase/Importers/PostImporter.swift SpudDataKit/Services/AppDatabase/Importers/CommentImporter.swift SpudDataKitTests/Outbox/ReconciliationGuardTests.swift
git commit -m "feat: preserve un-synced optimistic state on refresh imports"
```

---

### Task 8: Outbox network performer (send + authoritative reconcile)

**Files:**
- Create: `SpudDataKit/Services/Outbox/OutboxNetworkPerforming.swift`
- Test: `SpudDataKitTests/Outbox/OutboxNetworkPerformingTests.swift` (fake-based contract test; production impl verified by build + Task 11 integration)

**Interfaces:**
- Produces:
  - `protocol OutboxNetworkPerforming: Sendable { func perform(_ op: OutboxOperation) async throws }`
  - `struct LemmyOutboxPerformer: OutboxNetworkPerforming` holding `api: LemmyApi`, `appDatabase: AppDatabase`, `accountId: Int64`, `siteId: Int64`. `perform` switches on `op.kind`:
    - vote → `api.likePost/likeComment(status:)`; on success `appDatabase.upsertPost/upsertComment(from: response..._view, accountId:, siteId:, respectsPendingOutbox: false)`.
    - save → `api.savePost/saveComment(save:)`; reconcile as above.
    - hide → `api.hidePost(postIDs:[serverPostId], hide:)`; **no reconcile** (optimistic write stands).
  - Throws the raw error on api failure (caller classifies via Task 6).
- Consumes: the `respectsPendingOutbox: false` path from Task 7.

- [ ] **Step 1: Write the failing test (fake performer contract)**

```swift
import Testing
@testable import SpudDataKit

// A fake the OutboxService tests (Task 9) reuse. Lives in the test target.
actor FakeOutboxPerformer: OutboxNetworkPerforming {
    enum Outcome { case success; case fail(any Error) }
    var outcomeByKind: [OutboxKind: Outcome] = [:]
    private(set) var performed: [OutboxOperation] = []

    func setOutcome(_ outcome: Outcome, for kind: OutboxKind) { outcomeByKind[kind] = outcome }

    func perform(_ op: OutboxOperation) async throws {
        performed.append(op)
        if case let .fail(error) = outcomeByKind[op.kind] ?? .success { throw error }
    }
}

struct OutboxNetworkPerformingProtocolTests {
    @Test func fakeRecordsAndThrows() async throws {
        let fake = FakeOutboxPerformer()
        await fake.setOutcome(.fail(LemmyServiceError.requiresAuthentication), for: .vote)
        await #expect(throws: (any Error).self) {
            try await fake.perform(.init(entityType: .post, entityServerId: 1, desiredState: .vote(.liked)))
        }
        #expect(await fake.performed.count == 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails** — Expected: FAIL to compile (protocol missing).

- [ ] **Step 3: Write the protocol + production performer**

```swift
import Foundation
import LemmyKit

public protocol OutboxNetworkPerforming: Sendable {
    /// Sends `op` to the server. On success, reconciles authoritative state into
    /// the database (vote/save) or leaves the optimistic write standing (hide).
    /// Throws the underlying error on failure for the caller to classify.
    func perform(_ op: OutboxOperation) async throws
}

public struct LemmyOutboxPerformer: OutboxNetworkPerforming {
    let api: LemmyApi
    let appDatabase: AppDatabase
    let accountId: Int64
    let siteId: Int64

    public func perform(_ op: OutboxOperation) async throws {
        switch op.desiredState {
        case let .vote(status):
            switch op.entityType {
            case .post:
                let response = try await api.likePost(postID: Components.Schemas.PostID(op.entityServerId), status: status)
                try await appDatabase.upsertPost(from: response.post_view, accountId: accountId, siteId: siteId, respectsPendingOutbox: false)
            case .comment:
                let response = try await api.likeComment(commentID: Components.Schemas.CommentID(op.entityServerId), status: status)
                try await appDatabase.upsertComment(from: response.comment_view, accountId: accountId, siteId: siteId, respectsPendingOutbox: false)
            }
        case let .save(value):
            switch op.entityType {
            case .post:
                let response = try await api.savePost(postID: Components.Schemas.PostID(op.entityServerId), save: value)
                try await appDatabase.upsertPost(from: response.post_view, accountId: accountId, siteId: siteId, respectsPendingOutbox: false)
            case .comment:
                let response = try await api.saveComment(commentID: Components.Schemas.CommentID(op.entityServerId), save: value)
                try await appDatabase.upsertComment(from: response.comment_view, accountId: accountId, siteId: siteId, respectsPendingOutbox: false)
            }
        case let .hide(value):
            _ = try await api.hidePost(postIDs: [Components.Schemas.PostID(op.entityServerId)], hide: value)
            // No entity returned; optimistic write stands.
        }
    }
}
```

(Match the exact `api` method signatures from `LemmyService` — `likePost`, `likeComment`, `savePost`, `saveComment`, `hidePost`. Confirm `upsertComment(from:accountId:siteId:)` exists with that shape; if comment upsert needs a `postId`, thread it as the existing comment importer does.)

- [ ] **Step 4: Run `make project`, then run the test to verify it passes** — Expected: PASS (1 test). The production `LemmyOutboxPerformer` is exercised end-to-end in Task 11.

- [ ] **Step 5: Commit**

```bash
git add SpudDataKit/Services/Outbox/OutboxNetworkPerforming.swift SpudDataKitTests/Outbox/OutboxNetworkPerformingTests.swift
git commit -m "feat: add outbox network performer with authoritative reconcile"
```

---

### Task 9: OutboxService actor — enqueue, drain, failure events

**Files:**
- Create: `SpudDataKit/Services/Outbox/OutboxService.swift`
- Test: `SpudDataKitTests/Outbox/OutboxServiceTests.swift`

**Interfaces:**
- Consumes: `OutboxOperation`, `AppDatabase` (Task 5 queue methods), `OutboxNetworkPerforming` (Task 8), `OutboxFailureClass` (Task 6), `ReachabilityMonitoring`, `Broadcaster` (from `SpudUtilKit`).
- Produces:
  - `struct OutboxFailure: Sendable, Equatable { let entityType: OutboxEntityType; let entityServerId: Int64; let kind: OutboxKind }`
  - `protocol OutboxServiceType: Actor { func enqueue(_ op: OutboxOperation) async; func drainOnce() async; var failureEvents: AsyncStream<OutboxFailure> { get } }`
  - `actor OutboxService: OutboxServiceType` with `init(accountId: Int64, appDatabase: AppDatabase, performer: OutboxNetworkPerforming, reachability: ReachabilityMonitoring, now: @escaping @Sendable () -> Double)`
  - `func backoffDelay(attempts: Int64) -> Double` (exponential, capped ~300s)

Behavior:
- `enqueue`: `await appDatabase.enqueueOutboxOperation(op, accountId:, now: now())`; then `await drainOnce()`.
- `drainOnce`: fetch `dueOutboxOperations(accountId:, asOf: now())`. For each: `try await performer.perform(op-built-from-row)`; success → `removeOutboxOperation(id:)`; on throw → `OutboxFailureClass.classify(error, isOnline: await reachability.isOnline)`: `.transient` → `recordOutboxAttempt(id:, lastError:, nextAttemptAt: now() + backoffDelay(attempts+1))`; `.permanent` → `rollbackOutboxOperation(row)` then emit an `OutboxFailure` on the broadcaster.
- Build an `OutboxOperation` from a `PendingOperationRecord` via `OutboxDesiredState.decode(kind:raw:)`.
- `failureEvents` is `broadcaster.subscribe()`.

- [ ] **Step 1: Write the failing tests**

```swift
import LemmyKit
import Testing
@testable import SpudDataKit
@testable import SpudUtilKit

@MainActor
struct OutboxServiceTests {
    func makeService(_ appDatabase: AppDatabase, _ performer: FakeOutboxPerformer, online: Bool = true,
                     accountId: Int64 = 1) -> OutboxService {
        OutboxService(accountId: accountId, appDatabase: appDatabase, performer: performer,
                      reachability: StaticReachabilityMonitor(isOnline: online), now: { 1000 })
    }

    @Test func successfulDrainRemovesRow() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, postId) = try await seedPost(appDatabase, score: 0, voteStatus: nil)
        let performer = FakeOutboxPerformer()
        let service = makeService(appDatabase, performer, accountId: accountId)

        await service.enqueue(.init(entityType: .post, entityServerId: postId, desiredState: .vote(.liked)))

        #expect(await appDatabase.allOutboxOperations(accountId: accountId).isEmpty)
        #expect(await performer.performed.count == 1)
    }

    @Test func transientFailureKeepsRowAndSchedulesRetry() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, postId) = try await seedPost(appDatabase, score: 0, voteStatus: nil)
        let performer = FakeOutboxPerformer()
        await performer.setOutcome(.fail(URLError(.timedOut)), for: .vote)
        let service = makeService(appDatabase, performer, accountId: accountId)

        await service.enqueue(.init(entityType: .post, entityServerId: postId, desiredState: .vote(.liked)))

        let rows = try await appDatabase.allOutboxOperations(accountId: accountId)
        #expect(rows.count == 1)
        #expect(rows[0].attempts == 1)
        #expect((rows[0].nextAttemptAt ?? 0) > 1000) // backoff scheduled into the future
    }

    @Test func permanentFailureRollsBackAndEmits() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, postId) = try await seedPost(appDatabase, score: 5, voteStatus: nil)
        let performer = FakeOutboxPerformer()
        await performer.setOutcome(.fail(LemmyServiceError.requiresAuthentication), for: .vote)
        let service = makeService(appDatabase, performer, accountId: accountId)

        var events: [OutboxFailure] = []
        let stream = await service.failureEvents
        let collector = Task { for await event in stream { events.append(event); break } }

        await service.enqueue(.init(entityType: .post, entityServerId: postId, desiredState: .vote(.liked)))
        await collector.value

        #expect(await appDatabase.allOutboxOperations(accountId: accountId).isEmpty)
        let (score, vote) = try await readPostVote(appDatabase, accountId: accountId, serverPostId: postId)
        #expect(score == 5)  // rolled back
        #expect(vote == nil)
        #expect(events.first?.kind == .vote)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail** — Expected: FAIL to compile.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation
import SpudUtilKit

public struct OutboxFailure: Sendable, Equatable {
    public let entityType: OutboxEntityType
    public let entityServerId: Int64
    public let kind: OutboxKind
}

public protocol OutboxServiceType: Actor {
    func enqueue(_ op: OutboxOperation) async
    func drainOnce() async
    var failureEvents: AsyncStream<OutboxFailure> { get }
}

public actor OutboxService: OutboxServiceType {
    private let accountId: Int64
    private let appDatabase: AppDatabase
    private let performer: OutboxNetworkPerforming
    private let reachability: ReachabilityMonitoring
    private let now: @Sendable () -> Double
    private let broadcaster = Broadcaster<OutboxFailure>()

    public init(accountId: Int64, appDatabase: AppDatabase, performer: OutboxNetworkPerforming,
                reachability: ReachabilityMonitoring, now: @escaping @Sendable () -> Double) {
        self.accountId = accountId
        self.appDatabase = appDatabase
        self.performer = performer
        self.reachability = reachability
        self.now = now
    }

    public nonisolated var failureEvents: AsyncStream<OutboxFailure> { broadcaster.subscribe() }

    public func enqueue(_ op: OutboxOperation) async {
        do {
            try await appDatabase.enqueueOutboxOperation(op, accountId: accountId, now: now())
        } catch {
            return
        }
        await drainOnce()
    }

    public func drainOnce() async {
        let due: [PendingOperationRecord]
        do { due = try await appDatabase.dueOutboxOperations(accountId: accountId, asOf: now()) }
        catch { return }

        for record in due {
            guard let op = Self.operation(from: record) else { continue }
            do {
                try await performer.perform(op)
                try? await appDatabase.removeOutboxOperation(id: record.id!)
            } catch {
                let online = await reachability.isOnline
                switch OutboxFailureClass.classify(error, isOnline: online) {
                case .transient:
                    let next = now() + backoffDelay(attempts: record.attempts + 1)
                    try? await appDatabase.recordOutboxAttempt(id: record.id!, lastError: String(describing: error), nextAttemptAt: next)
                case .permanent:
                    try? await appDatabase.rollbackOutboxOperation(record)
                    broadcaster.send(OutboxFailure(entityType: op.entityType, entityServerId: op.entityServerId, kind: op.kind))
                }
            }
        }
    }

    func backoffDelay(attempts: Int64) -> Double {
        let base = 2.0
        let delay = base * pow(2.0, Double(max(0, attempts - 1)))
        return min(delay, 300)
    }

    private static func operation(from record: PendingOperationRecord) -> OutboxOperation? {
        guard let entityType = OutboxEntityType(rawValue: record.entityType),
              let kind = OutboxKind(rawValue: record.kind) else { return nil }
        let desired = OutboxDesiredState.decode(kind: kind, raw: record.desiredState)
        return OutboxOperation(entityType: entityType, entityServerId: record.entityServerId, desiredState: desired)
    }
}
```

(Confirm `Broadcaster<Value>` API — `init()`, `subscribe() -> AsyncStream`, `send(_:)` — matches `SpudUtilKit`'s `Broadcaster` used by `@UserDefaultsBacked`. The `reachability.isOnline` access is `@MainActor`; if the actor can't read it directly, capture an `isOnline` snapshot via an injected `@Sendable () async -> Bool` or read it before the loop.)

- [ ] **Step 4: Run the tests to verify they pass** — Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add SpudDataKit/Services/Outbox/OutboxService.swift SpudDataKitTests/Outbox/OutboxServiceTests.swift
git commit -m "feat: add OutboxService actor with enqueue, drain, and failure events"
```

---

### Task 10: Auto-drain triggers (reachability + backoff timer + drain-all)

**Files:**
- Modify: `SpudDataKit/Services/Outbox/OutboxService.swift`
- Test: `SpudDataKitTests/Outbox/OutboxServiceTriggersTests.swift`

**Interfaces:**
- Produces (added to `OutboxServiceType` / `OutboxService`):
  - `func drainAll() async` — drains regardless of `nextAttemptAt` (used on reconnect / foreground): fetch `allOutboxOperations`, reset is not needed — just attempt every row whose `nextAttemptAt <= now` OR force-attempt all. Use `dueOutboxOperations(asOf: .greatestFiniteMagnitude)` to include backed-off rows when connectivity returns.
  - `func start() async` — subscribes to `reachability.statusStream`; on a transition to `true`, calls `drainAll()`. Spawns a long-lived task; safe to call once at construction.

Behavior: when reachability flips online, immediately retry everything (connectivity is the strongest signal that a transient failure will now succeed). Keep the backoff timer simple: after a transient failure, `drainOnce` is re-invoked by `start`'s loop or by the next enqueue; a dedicated timer is optional. For the test, drive it through `StaticReachabilityMonitor.setOnline`.

- [ ] **Step 1: Write the failing test**

```swift
import LemmyKit
import Testing
@testable import SpudDataKit
@testable import SpudUtilKit

@MainActor
struct OutboxServiceTriggersTests {
    @Test func reconnectDrainsBackedOffRows() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, postId) = try await seedPost(appDatabase, score: 0, voteStatus: nil)
        let performer = FakeOutboxPerformer()
        await performer.setOutcome(.fail(URLError(.timedOut)), for: .vote)
        let monitor = StaticReachabilityMonitor(isOnline: false)
        let service = OutboxService(accountId: accountId, appDatabase: appDatabase, performer: performer,
                                    reachability: monitor, now: { 1000 })
        await service.start()

        // Offline enqueue: transient, row stays.
        await service.enqueue(.init(entityType: .post, entityServerId: postId, desiredState: .vote(.liked)))
        #expect(try await appDatabase.allOutboxOperations(accountId: accountId).count == 1)

        // Now succeed and come back online; reconnect should drain.
        await performer.setOutcome(.success, for: .vote)
        monitor.setOnline(true)
        try await Task.sleep(nanoseconds: 50_000_000) // let the reachability task run
        #expect(try await appDatabase.allOutboxOperations(accountId: accountId).isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails** — Expected: FAIL to compile (`start`/`drainAll` missing).

- [ ] **Step 3: Implement triggers**

```swift
// Add to OutboxService:

private var started = false

public func start() async {
    guard !started else { return }
    started = true
    let stream = reachability.statusStream
    Task { [weak self] in
        var wasOnline: Bool?
        for await online in stream {
            if online, wasOnline != true {
                await self?.drainAll()
            }
            wasOnline = online
        }
    }
}

public func drainAll() async {
    // Include backed-off rows: treat everything as due.
    let all: [PendingOperationRecord]
    do { all = try await appDatabase.dueOutboxOperations(accountId: accountId, asOf: .greatestFiniteMagnitude) }
    catch { return }
    await drain(records: all)
}
```

Refactor `drainOnce` to call a shared `private func drain(records:)` so `drainAll` reuses the per-row logic. Keep Task 9's tests green.

- [ ] **Step 4: Run the tests to verify they pass** — Expected: PASS (Task 9 tests + this one).

- [ ] **Step 5: Commit**

```bash
git add SpudDataKit/Services/Outbox/OutboxService.swift SpudDataKitTests/Outbox/OutboxServiceTriggersTests.swift
git commit -m "feat: drain outbox on reconnect"
```

---

### Task 11: Wire outbox into LemmyService + account scope

**Files:**
- Modify: `SpudDataKit/Services/Lemmy/LemmyService.swift` (delegate vote/setSaved/hidePost; add vote signed-out gate; hold an `OutboxService`)
- Modify: `SpudDataKit/Services/Account/AccountService.swift:392` (construct `OutboxService` + `LemmyOutboxPerformer`; pass reachability)
- Modify: `SpudDataKit/Services/Account/AccountScope.swift` (expose `outboxFailureEvents`)
- Test: `SpudDataKitTests/Outbox/LemmyServiceOutboxDelegationTests.swift`

**Interfaces:**
- Consumes: `OutboxService`, `LemmyOutboxPerformer`, `ReachabilityMonitoring`.
- Produces: `LemmyService` gains a stored `outbox: OutboxService`; `vote(serverPostId:)`, `vote(serverCommentId:)`, `setSaved(...)`, `hidePost(...)` become thin delegations: signed-out gate (add to the two `vote` methods — match `setSaved`/`hidePost`'s `guard !accountIsSignedOut else { throw .requiresAuthentication }`), build `OutboxOperation` (vote uses `currentVoteStatus.effectiveAction(for: action)` to derive the absolute `LikeStatus`), `await outbox.enqueue(op)`. Remove the inline `api.likePost`/`savePost`/`hidePost` calls and their mirrors from these methods (now in the performer).
- `AccountScope` gains `var outboxFailureEvents: AsyncStream<OutboxFailure>` forwarding the account's `OutboxService.failureEvents`.

Construction: in `AccountService` where `LemmyService(...)` is built (line ~392), also build `LemmyOutboxPerformer(api:appDatabase:accountId:siteId:)` and `OutboxService(accountId:appDatabase:performer:reachability:now:)`, call `await outbox.start()`, and pass it into `LemmyService.init`. `AccountService` must receive a `ReachabilityMonitoring` (from `DependencyContainer`) — thread it through if not already present. `accountId`/`siteId` come from the existing account row lookup (`accountSiteIds()` pattern).

- [ ] **Step 1: Write the failing test**

```swift
import LemmyKit
import Testing
@testable import SpudDataKit

@MainActor
struct LemmyServiceOutboxDelegationTests {
    @Test func voteEnqueuesOptimisticStateImmediately() async throws {
        // Build a LemmyService backed by an in-memory DB, a never-completing fake
        // api (to prove we do NOT wait on the network), and a real OutboxService.
        // Assert the post's voteStatus/score reflect the vote right after the
        // await returns, before any network response.
        // (Construct via the same seams AccountService uses; inject a fake api whose
        //  likePost suspends forever.)
    }
}
```

(Flesh out the test with the project's existing `LemmyService` test construction helpers. The key assertion: after `await lemmyService.vote(serverPostId:vote:)` returns, `readPostVote` already shows the optimistic value while the fake api call is still suspended — proving the UI no longer blocks on the network. If wiring a full `LemmyService` in a unit test is impractical, assert the equivalent at the `OutboxService` seam and cover delegation by build + the manual checklist in Task 13.)

- [ ] **Step 2: Run test to verify it fails.**

- [ ] **Step 3: Implement the delegation + wiring** — edit `LemmyService.vote/setSaved/hidePost` to delegate; add the vote signed-out gate; construct and `start()` the `OutboxService` in `AccountService`; expose `outboxFailureEvents` on `AccountScope`. Build with `make project` then the framework scheme.

- [ ] **Step 4: Run the test + full `SpudDataKitTests` suite** — Expected: PASS; no regressions. Verify the app target still builds: `python3 .../build_and_test.py --scheme Spud`.

- [ ] **Step 5: Commit**

```bash
git add SpudDataKit/Services/Lemmy/LemmyService.swift SpudDataKit/Services/Account/AccountService.swift SpudDataKit/Services/Account/AccountScope.swift SpudDataKitTests/Outbox/LemmyServiceOutboxDelegationTests.swift
git commit -m "feat: route vote/save/hide through the optimistic outbox"
```

---

### Task 12: Toast presenter (app target)

**Files:**
- Create: `Spud/Scenes/Common/Toast/ToastPresenter.swift`
- (Optional) Test: `SpudSnapshotTests/.../ToastSnapshotTests.swift` (iPhone 14 Pro portrait) — optional; the presenter is mostly imperative UIKit.

**Interfaces:**
- Produces: `@MainActor final class ToastPresenter` with `func show(_ message: String, in window: UIWindow)` — presents a small, non-blocking, auto-dismissing label/banner near the bottom, with a fade in/out and a ~2s dwell. No queueing complexity needed; if one is showing, replace its text and reset the timer.

- [ ] **Step 1: Implement the presenter** — a self-contained UIKit view added to the window, constrained above the safe-area bottom, with `UIView.animate` fade and a `Task`/timer auto-dismiss. No emojis. Follow existing view styling tokens from `SpudUIKit` for color/typography.

- [ ] **Step 2: Build** — `make project` then `python3 .../build_and_test.py --scheme Spud`. Expected: builds clean.

- [ ] **Step 3: (Optional) snapshot test** — if added, record on iPhone 14 Pro portrait per the snapshot constraint.

- [ ] **Step 4: Commit**

```bash
git add Spud/Scenes/Common/Toast/ToastPresenter.swift
git commit -m "feat: add non-blocking toast presenter"
```

---

### Task 13: App wiring — failure toasts, foreground drain, simplify call sites

**Files:**
- Modify: app entry (SceneDelegate / AppCoordinator — locate via `sceneWillEnterForeground` / where `AccountScope` is created for the active account)
- Modify: `Spud/Scenes/PostList/PostListViewController.swift`, `Spud/Scenes/PostDetail/Content/PostDetailViewController.swift`, `Spud/Scenes/MediaViewer/MediaViewerViewController.swift`, `Spud/Scenes/Preferences/HiddenAndMuted/HiddenAndMutedViewModel.swift`

**Interfaces:**
- Consumes: `AccountScope.outboxFailureEvents`, `ToastPresenter` (Task 12).

Changes:
- Subscribe to the active account's `outboxFailureEvents` (an `AsyncStream`); on each `OutboxFailure`, map `kind` to copy ("Couldn't vote" / "Couldn't save" / "Couldn't hide") and call `ToastPresenter.show(_:in:)` on the key window.
- On `sceneWillEnterForeground` (and app launch, alongside the existing Spotlight reindex hook), call `await scope.outbox.drainAll()` for the active account (expose a `drainPendingOutbox()` on the scope if needed).
- Simplify the vote/save/hide call sites: drop the `do/catch` that called `alertService.handle(error, for: .vote)` (network errors no longer surface here — `vote()` returns fast). Keep the instant haptic. Keep the signed-out path: `vote/setSaved/hidePost` still `throw .requiresAuthentication` synchronously when signed out, so retain a `catch` that shows the existing sign-in CTA (mirror how `setSaved`'s call site already gates). The post-list vote handler at `PostListViewController.swift:1220` and post-detail `voteOnPost`/`voteOnComment` are the primary edits.

- [ ] **Step 1: Implement the wiring + call-site simplification.**

- [ ] **Step 2: Build** — `make project` then `python3 .../build_and_test.py --scheme Spud`. Expected: builds clean (the pre-existing benign rpath warning is acceptable).

- [ ] **Step 3: Manual verification on a booted simulator** (tap automation is unreliable here — verify by hand). Keep one simulator booted. Check:
  1. Upvote a post/comment → tint + score change **instantly**, no perceptible delay.
  2. Toggle a vote off → reverts instantly; with network on, no toast.
  3. Save and hide → instant; hide removes the post from the feed immediately.
  4. Airplane mode → vote → optimistic state holds; re-enable network → it syncs (no toast). Confirm the row drains (query the live App Group DB per CLAUDE.md if needed).
  5. Force-quit while a vote is pending offline → relaunch → optimistic state still present and drains on reconnect.
  6. Signed-out account → vote → sign-in CTA shows (no optimistic apply).

- [ ] **Step 4: Commit**

```bash
git add Spud/...
git commit -m "feat: show vote/save/hide failure toasts and simplify call sites"
```

---

## Self-Review

**Spec coverage:**
- Durable persisted queue → Task 3 (table/record), Task 5 (writes). ✓
- Optimistic projection (immediate UI) → Task 2 (math), Task 4 (writes), Task 5 (enqueue). ✓
- Coalescing per (account, target, kind) + toggle-to-baseline → Task 3 (unique key), Task 5 (enqueue logic + tests). ✓
- Transient-vs-permanent retry, rollback on permanent → Task 6 (classify), Task 9 (drain policy). ✓
- Retry triggers (enqueue, reconnect, foreground, backoff) → Task 9 (enqueue/backoff), Task 10 (reconnect), Task 13 (foreground). ✓
- Reconciliation guard → Task 7. ✓
- Set-state send + hide-no-reconcile → Task 8. ✓
- Failure toast (non-blocking) → Task 12 (presenter), Task 13 (wiring). ✓
- Signed-out gate → Task 11 (vote gate), Task 13 (CTA). ✓
- Vote + save + hide, post + comment (hide post-only) → Tasks 4/5/8 cover all kind×entity pairs; hide guarded to post. ✓
- Drafts non-goal → not implemented (correct). ✓

**Placeholder scan:** Task 11's unit test is a described stub (acknowledged: full `LemmyService` construction in a unit test may be impractical; fallback to the `OutboxService` seam + manual checklist is stated). Task 5's implementation includes an explicit "simplify this" refactor note with the target shape and the tests as the contract — acceptable because the behavioral contract (Step 1 tests) is concrete. No "TODO/TBD/handle edge cases" placeholders remain.

**Type consistency:** `OutboxOperation`/`OutboxDesiredState`/`OutboxKind`/`OutboxEntityType` (T1) are used consistently in T5/T8/T9. `OutboxProjection.dbVoteStatus`/`voteScoreDelta`/`voteStatus(fromDB:)` (T2) used in T5. `PendingOperationRecord` fields (T3) match the `enqueue`/`due`/`rollback` SQL (T5) and the `OutboxService` row decoding (T9). `OutboxNetworkPerforming.perform` (T8) called in T9. `OutboxFailure` (T9) consumed in T13. `respectsPendingOutbox` (T7) passed `false` by the performer (T8). Consistent.

**Known integration risks to verify during implementation (not plan gaps):** exact column names (`postId`, `localCommentId`, `accountId`, `score`, `voteStatus`, `isSaved`, `isHidden`), `Broadcaster` API surface, `@MainActor` reachability access from the actor, and `upsertComment` parameter shape. Each task says to confirm against the real code.
