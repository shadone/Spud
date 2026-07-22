# Comment Fetching Completeness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Spud's comment tree match what the server actually has on Lemmy v3, Lemmy v4 and PieFed, make re-importing a tree safe to do while someone is reading it, and make any remaining partial load visible instead of silent.

**Architecture:** Five layers, built bottom-up. `CommentImporter.upsertComments` stops destroying and rebuilding element rows and instead reconciles them, so row identity (and therefore collapse state and scroll position) survives a re-import. LemmyKit's v3 requests get a deeper tree and a full-size "load more" page. `LemmyService.fetchComments` then paginates — importing page 1 immediately and finishing the rest in the background — and reports whether it exhausted the listing. The post-detail view model surfaces what is left over as a terminal "Load more comments" row and a toast on a mid-pagination failure.

**Tech Stack:** Swift 6 (strict concurrency), UIKit, GRDB, Swift Testing, XcodeGen, LemmyKit (remote SPM pin).

## Global Constraints

- Design spec: `docs/superpowers/specs/2026-07-22-comment-fetching-completeness-design.md`. Read it before starting.
- `postCommentTreeMaxDepth` becomes **15**. The v3 comment listing page limit constant is **50** — Lemmy's ceiling; `limit=300` fails with `{"error":"couldnt_get_comments"}`.
- The comment page bound is **10 pages**, mirroring the existing `LemmyService.maxSubtreeChildCountPages`.
- Never derive "is the tree complete" from the post's comment counter. The server's count and the returned row count legitimately differ (a 135-comment post returns 138 rows). Completeness comes only from whether pagination had a cursor left.
- The header's comment count keeps coming from `PostView.counts`. Do not change that.
- No emojis in code, comments, docs or commit messages. Conventional commit subjects.
- Run `mint run swiftformat <paths>` **before** the final test run of each task, never after.
- Unit tests are Swift Testing (`@Test func`, `#expect`), not XCTest. LemmyKit's `GetListNeutralTests` is XCTest — match the file you are editing.
- Two simulators may be booted. Target the iOS 26.3 iPhone 17 Pro **by id**; do not shut down another agent's sim. Get the id with `xcrun simctl list devices booted`.
- This checkout is shared with other agents. Stage explicit paths, never `git add -A`. Verify `git branch --show-current` before committing. Another agent currently has uncommitted edits in `Spud/CLAUDE.md` — do not commit their hunks.

**Test command template** (substitute the sim id from `xcrun simctl list devices booted`):

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud
SIM=$(xcrun simctl list devices booted | grep "iPhone 17 Pro" | grep -oE '[0-9A-F-]{36}' | head -1)
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudDataKitTests/<SuiteName> \
  -destination "platform=iOS Simulator,id=$SIM" \
  -skipPackagePluginValidation -skipMacroValidation test 2>&1 \
  | grep -viE "remote service|passcode|DTDKRemote|LLVM Profile" \
  | grep -E "✘|✔|Test run with|error:"
```

---

## File Structure

**SpudDataKit**
- Modify `SpudDataKit/Services/AppDatabase/Importers/CommentImporter.swift` — `upsertComments` reconciles instead of rebuilding (Task 1).
- Create `SpudDataKit/Services/Lemmy/CommentFetchCompletion.swift` — the value type describing how a comment fetch ended (Task 3).
- Modify `SpudDataKit/Services/Lemmy/LemmyService.swift` — `fetchComments` paginates and returns a completion (Task 3).

**LemmyKit** (separate repo, `/Users/denis/dev/info.ddenis/Spud/LemmyKit`)
- Modify `Sources/LemmyKit/LemmyApi+GetCommentsNeutral.swift` — depth constant, parent-scoped page limit (Task 2).

**Spud app**
- Modify `Spud/Scenes/PostDetail/Content/PostDetailViewModel.swift` — track outstanding pages and partial failure (Tasks 4, 5).
- Modify `Spud/Scenes/PostDetail/Content/PostDetailViewController.swift` — the terminal "Load more comments" row and the partial-failure toast (Tasks 4, 5).
- Create `Spud/Scenes/PostDetail/Content/Comment/PostDetailLoadMoreCommentsCell.swift` — the terminal row's cell (Task 4). New source files need `make project` (XcodeGen) before they compile.

**How the first paint works** — do not "fix" this: `fetchComments` awaits the whole page walk, but the tree does not wait for it. Post detail renders from a GRDB *observation* of the element rows, not from the fetch's return value, so page 1's `mirrorCommentsToAppDatabase` puts comments on screen while later pages are still in flight. `CommentsBackground.decide` returns `.hidden` as soon as `hasComments` is true, so the skeleton is replaced at page 1 even though `isLoadingComments` stays true until the walk finishes.

**Tests**
- Modify `SpudDataKitTests/CommentImporterStableIdentityTests.swift` (new file, Task 1).
- Modify `LemmyKit/Tests/LemmyKitTests/GetListNeutralTests.swift` (Task 2).
- Create `SpudDataKitTests/LemmyServiceCommentPaginationTests.swift` (Task 3).
- Create `SpudTests/PostDetailPartialCommentLoadTests.swift` (Tasks 4, 5).

---

### Task 1: Stable comment row identity

`upsertComments` currently deletes every `CommentElementRecord` for `(post, sortType)` and reinserts. Because `CommentElementRecord.id` is an auto-increment rowid and the diffable snapshot keys on it (`Item.comment(elementId: Int64)`), each re-import mints new identities and `PostDetailViewModel.swift:523`'s `collapsedElementIds.formIntersection(existingIds)` empties. Reconcile instead.

Identity keys: **the local comment row id** for real rows (stable — comment rows are upserted, never deleted here) and **`moreParentId`, a server comment id** for placeholders.

There is no unique index on `(postId, sortType, position)` (see the `commentElement` table in `AppDatabase+Migrations.swift`), so rewriting positions in place is safe. The read side orders by `commentElement.position ASC`.

**Files:**
- Modify: `SpudDataKit/Services/AppDatabase/Importers/CommentImporter.swift:55-131`
- Test: `SpudDataKitTests/CommentImporterStableIdentityTests.swift` (create)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `AppDatabase.upsertComments(forServerPostId:accountId:siteId:sortType:comments:)` — unchanged signature, `async throws -> Void`. Behavior change only: element ids are preserved for comments still in the tree.

- [ ] **Step 1: Write the failing test**

Create `SpudDataKitTests/CommentImporterStableIdentityTests.swift`. The `seed` and `elements` helpers below are copied verbatim from `SpudDataKitTests/AppDatabase/SpliceMoreCommentsTests.swift:20-57` — `upsertComments` silently no-ops when the post row is missing, so the post must really be seeded or the tests pass for the wrong reason.

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

private typealias Person = Lemmy.Person
private typealias Community = Lemmy.Community
private typealias Post = Lemmy.Post
private typealias CommentView = Lemmy.CommentView

/// `upsertComments` must reconcile the stored comment element rows, not rebuild
/// them. The diffable snapshot on post detail keys on `CommentElementRecord.id`,
/// and `PostDetailViewModel` intersects its collapse set against the surviving
/// ids -- so an import that mints fresh ids silently drops the reader's collapse
/// state and churns every row identity.
@MainActor
struct CommentImporterStableIdentityTests {
    /// Seeds instance/site/account/post and returns the ids needed to import
    /// comments. Copied from `SpliceMoreCommentsTests`.
    private func seed(
        _ appDatabase: AppDatabase,
        serverPostId: Int64
    ) async throws -> (accountId: Int64, siteId: Int64, postRowId: Int64, person: Person, community: Community, post: Post) {
        let (accountId, siteId) = try await appDatabase.writer.write { db -> (Int64, Int64) in
            var instance = InstanceRecord(actorId: "https://example.com")
            try instance.insert(db)
            var site = SiteRecord(instanceId: instance.id!)
            try site.insert(db)
            var account = AccountRecord(
                siteId: site.id!,
                accountKeychainId: "keychain-stable-identity",
                isSignedOutAccountType: false
            )
            try account.insert(db)
            return (account.id!, site.id!)
        }
        let person = Person.fake
        let community = Community.fake
        let post = Post.fake(creator: person, community: community, id: Lemmy.PostID(serverPostId))
        let postRowId = try await appDatabase.upsertPost(
            from: .fake(post: post, creator: person, community: community),
            accountId: accountId,
            siteId: siteId
        )
        return (accountId, siteId, postRowId, person, community, post)
    }

    private func elements(_ appDatabase: AppDatabase, postRowId: Int64) async throws -> [CommentElementRecord] {
        try await appDatabase.writer.read { db in
            try CommentElementRecord
                .filter(Column("postId") == postRowId)
                .filter(Column("sortType") == Lemmy.CommentSortType.Hot.rawValue)
                .order(Column("position"))
                .fetchAll(db)
        }
    }

    /// A comment present in both imports keeps its element row id.
    @Test
    func reimportPreservesElementIdForSurvivingComment() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let seeded = try await seed(appDatabase, serverPostId: 1)

        let one = CommentView.fake(
            comment: .fake(id: 10, post: seeded.post, creator: seeded.person, parent: .root),
            creator: seeded.person, post: seeded.post, community: seeded.community, childCount: 0
        )
        let two = CommentView.fake(
            comment: .fake(id: 11, post: seeded.post, creator: seeded.person, parent: .root),
            creator: seeded.person, post: seeded.post, community: seeded.community, childCount: 0
        )

        try await appDatabase.upsertComments(
            forServerPostId: 1, accountId: seeded.accountId, siteId: seeded.siteId,
            sortType: .Hot, comments: [one]
        )
        let firstIds = try await elements(appDatabase, postRowId: seeded.postRowId).compactMap(\.id)

        try await appDatabase.upsertComments(
            forServerPostId: 1, accountId: seeded.accountId, siteId: seeded.siteId,
            sortType: .Hot, comments: [one, two]
        )
        let secondIds = try await elements(appDatabase, postRowId: seeded.postRowId).compactMap(\.id)

        #expect(firstIds.count == 1)
        #expect(secondIds.count == 2)
        #expect(
            secondIds.first == firstIds.first,
            "the comment present in both imports must keep its element row id"
        )
    }

    /// A comment that leaves the tree has its element row deleted.
    @Test
    func reimportDeletesElementForDepartedComment() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let seeded = try await seed(appDatabase, serverPostId: 1)

        let one = CommentView.fake(
            comment: .fake(id: 10, post: seeded.post, creator: seeded.person, parent: .root),
            creator: seeded.person, post: seeded.post, community: seeded.community, childCount: 0
        )
        let two = CommentView.fake(
            comment: .fake(id: 11, post: seeded.post, creator: seeded.person, parent: .root),
            creator: seeded.person, post: seeded.post, community: seeded.community, childCount: 0
        )

        try await appDatabase.upsertComments(
            forServerPostId: 1, accountId: seeded.accountId, siteId: seeded.siteId,
            sortType: .Hot, comments: [one, two]
        )
        // Hoist the await out of #expect: SwiftFormat mangles `#expect(await …)`
        // into invalid syntax (`#expectawait(…)`).
        let beforeCount = try await elements(appDatabase, postRowId: seeded.postRowId).count
        #expect(beforeCount == 2)

        try await appDatabase.upsertComments(
            forServerPostId: 1, accountId: seeded.accountId, siteId: seeded.siteId,
            sortType: .Hot, comments: [one]
        )
        let remaining = try await elements(appDatabase, postRowId: seeded.postRowId)
        #expect(remaining.count == 1)
    }

    /// A "load more" placeholder reconciles on its `moreParentId`, so it too
    /// keeps its element row id across a re-import.
    @Test
    func reimportPreservesPlaceholderElementId() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let seeded = try await seed(appDatabase, serverPostId: 1)

        // One top-level comment claiming 5 children none of which are loaded --
        // `findCommentsWithMissingChildren` flags it, so a placeholder follows it.
        let withMissingChildren = [
            CommentView.fake(
                comment: .fake(id: 10, post: seeded.post, creator: seeded.person, parent: .root, childCount: 5),
                creator: seeded.person, post: seeded.post, community: seeded.community, childCount: 5
            ),
        ]

        try await appDatabase.upsertComments(
            forServerPostId: 1, accountId: seeded.accountId, siteId: seeded.siteId,
            sortType: .Hot, comments: withMissingChildren
        )
        let firstPlaceholders = try await elements(appDatabase, postRowId: seeded.postRowId)
            .filter { $0.commentId == nil }
            .compactMap(\.id)

        try await appDatabase.upsertComments(
            forServerPostId: 1, accountId: seeded.accountId, siteId: seeded.siteId,
            sortType: .Hot, comments: withMissingChildren
        )
        let secondPlaceholders = try await elements(appDatabase, postRowId: seeded.postRowId)
            .filter { $0.commentId == nil }
            .compactMap(\.id)

        #expect(firstPlaceholders.count == 1)
        #expect(secondPlaceholders == firstPlaceholders)
    }

    /// Reconciliation must not disturb display order: positions are rewritten in
    /// place and the read side orders by `position ASC`.
    @Test
    func reimportKeepsTreeOrder() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let seeded = try await seed(appDatabase, serverPostId: 1)

        let ten = CommentView.fake(
            comment: .fake(id: 10, post: seeded.post, creator: seeded.person, parent: .root),
            creator: seeded.person, post: seeded.post, community: seeded.community, childCount: 0
        )

        try await appDatabase.upsertComments(
            forServerPostId: 1, accountId: seeded.accountId, siteId: seeded.siteId,
            sortType: .Hot, comments: [ten]
        )
        try await appDatabase.upsertComments(
            forServerPostId: 1, accountId: seeded.accountId, siteId: seeded.siteId,
            sortType: .Hot,
            comments: [
                ten,
                CommentView.fake(
                    comment: .fake(id: 11, post: seeded.post, creator: seeded.person, parent: .root.appending(10)),
                    creator: seeded.person, post: seeded.post, community: seeded.community, childCount: 0
                ),
                CommentView.fake(
                    comment: .fake(id: 12, post: seeded.post, creator: seeded.person, parent: .root),
                    creator: seeded.person, post: seeded.post, community: seeded.community, childCount: 0
                ),
            ]
        )

        let rows = try await elements(appDatabase, postRowId: seeded.postRowId)
        #expect(rows.map(\.position) == [0, 1, 2])
        #expect(rows.map(\.depth) == [0, 1, 0])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run the test command template with `-only-testing:SpudDataKitTests/CommentImporterStableIdentityTests`.

Expected: `reimportPreservesElementIdForSurvivingComment` and `reimportPreservesPlaceholderElementId` FAIL (the ids differ after the second import). The delete and order tests may already pass — that is fine, they are regression guards.

- [ ] **Step 3: Implement the reconciling upsert**

In `SpudDataKit/Services/AppDatabase/Importers/CommentImporter.swift`, replace the body of `upsertComments` from the `let sortTypeRaw` line through the end of the `for view in ordered` loop with:

```swift
            let sortTypeRaw = sortType.rawValue

            // Reconcile the element rows rather than rebuilding them. The
            // post-detail diffable snapshot keys on `CommentElementRecord.id`
            // and the view model intersects its collapse set against the
            // surviving ids, so minting fresh ids on every import would silently
            // drop the reader's collapse state and churn every row identity.
            // Real rows are keyed by their local comment row id; "load more"
            // placeholders by `moreParentId` (a server comment id), which is
            // already the semantic key `spliceMoreComments` looks them up by.
            let existingElements = try CommentElementRecord
                .filter(Column("postId") == postRowId)
                .filter(Column("sortType") == sortTypeRaw)
                .fetchAll(db)

            var elementByCommentRowId: [Int64: CommentElementRecord] = [:]
            var elementByMoreParentId: [Int64: CommentElementRecord] = [:]
            for element in existingElements {
                if let commentId = element.commentId {
                    elementByCommentRowId[commentId] = element
                } else if let moreParentId = element.moreParentId {
                    elementByMoreParentId[moreParentId] = element
                }
            }

            let commentsWithMissingChildren: Set<Lemmy.CommentID> = Set(
                LemmyCommentImportHelper
                    .findCommentsWithMissingChildren(comments)
                    .map { Lemmy.CommentID($0.comment.id) }
            )

            let ordered = LemmyCommentImportHelper.sort(comments: comments)

            var survivingElementIds: Set<Int64> = []
            var elementPosition: Int64 = 0
            for view in ordered {
                let path = CommentPath(path: view.comment.path)
                let depth = Int64(path.depth)

                let commentRowId = try Self.upsertComment(
                    from: view,
                    accountId: accountId,
                    postRowId: postRowId,
                    siteId: siteId,
                    respectsPendingOutbox: true,
                    in: db
                )

                var element = elementByCommentRowId[commentRowId] ?? CommentElementRecord(
                    postId: postRowId,
                    commentId: commentRowId,
                    position: elementPosition,
                    depth: depth,
                    sortType: sortTypeRaw
                )
                element.position = elementPosition
                element.depth = depth
                // A row that was a comment stays a comment; clear any stale
                // placeholder fields defensively.
                element.moreChildCount = nil
                element.moreParentId = nil
                try element.save(db)
                if let id = element.id { survivingElementIds.insert(id) }
                elementPosition += 1

                if commentsWithMissingChildren.contains(Lemmy.CommentID(view.comment.id)) {
                    let moreParentId = Int64(view.comment.id)
                    var placeholder = elementByMoreParentId[moreParentId] ?? CommentElementRecord(
                        postId: postRowId,
                        commentId: nil,
                        position: elementPosition,
                        depth: depth + 1,
                        sortType: sortTypeRaw,
                        moreChildCount: view.comment.childCount,
                        moreParentId: moreParentId
                    )
                    placeholder.commentId = nil
                    placeholder.position = elementPosition
                    placeholder.depth = depth + 1
                    placeholder.moreChildCount = view.comment.childCount
                    placeholder.moreParentId = moreParentId
                    try placeholder.save(db)
                    if let id = placeholder.id { survivingElementIds.insert(id) }
                    elementPosition += 1
                }
            }

            // Delete only the rows that left the tree.
            try CommentElementRecord
                .filter(Column("postId") == postRowId)
                .filter(Column("sortType") == sortTypeRaw)
                .filter(!survivingElementIds.contains(Column("id")))
                .deleteAll(db)
```

Delete the old `try CommentElementRecord … .deleteAll(db)` block that ran *before* the loop, and the old `commentsWithMissingChildren` / `ordered` / `elementPosition` declarations that this replaces. Do not touch `spliceMoreComments`.

- [ ] **Step 4: Run the test to verify it passes**

Run the same command as Step 2. Expected: all four tests PASS.

- [ ] **Step 5: Run the whole data-layer suite for regressions**

Run the test command template with `-only-testing:SpudDataKitTests`.

Expected: `✔ Test run with <N> tests in <M> suites passed`. Pay particular attention to any suite named `*MoreComments*`, `*SubtreeChildCount*` or `*FetchPersistence*` — those exercise the import path this task changed.

- [ ] **Step 6: Format and commit**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud
mint run swiftformat SpudDataKit/Services/AppDatabase/Importers/CommentImporter.swift SpudDataKitTests/CommentImporterStableIdentityTests.swift
git add SpudDataKit/Services/AppDatabase/Importers/CommentImporter.swift SpudDataKitTests/CommentImporterStableIdentityTests.swift
git commit -m "fix: reconcile comment element rows instead of rebuilding them

upsertComments deleted every element row for (post, sortType) and reinserted,
minting fresh auto-increment ids. The post-detail diffable snapshot keys on
CommentElementRecord.id and the view model intersects its collapse set against
the surviving ids, so every re-import - including every pull-to-refresh -
silently discarded the reader's collapse state and churned every row identity.

Element rows now reconcile on the local comment row id (real rows) and on
moreParentId (placeholders), updating position and depth in place and deleting
only rows whose comment left the tree.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: LemmyKit wire — deeper tree, full-size load-more page

Two independent wire defects, both in the v3 paths of the neutral comment surface.

**Files:**
- Modify: `/Users/denis/dev/info.ddenis/Spud/LemmyKit/Sources/LemmyKit/LemmyApi+GetCommentsNeutral.swift`
- Test: `/Users/denis/dev/info.ddenis/Spud/LemmyKit/Tests/LemmyKitTests/GetListNeutralTests.swift`
- Modify: `/Users/denis/dev/info.ddenis/Spud/Spud/project.yml:37` (the pin)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `LemmyApi.postCommentTreeMaxDepth: Int32` (value 15) and `LemmyApi.commentListingPageLimit: Components.Parameters.Limit` (i.e. `Int64`, value 50). Task 3 does not reference either directly.

- [ ] **Step 1: Write the failing test**

In `LemmyKit/Tests/LemmyKitTests/GetListNeutralTests.swift`, find `testGetCommentsNeutralV3SendsListingTypeAndMaxDepth` and update its `max_depth` assertion to 15, then add the parent-scoped test immediately after it. This file is **XCTest**, not Swift Testing.

```swift
    /// The v3 post-scoped fetch sends the tree depth, and deliberately sends NO
    /// `limit`: with `max_depth` set the server ignores `limit` entirely (and
    /// `page`), capping the response at 300 comments, so sending one would only
    /// be misleading.
    func testGetCommentsNeutralV3SendsListingTypeAndMaxDepth() async throws {
        let transport = try PathCapturingStubTransport(responseBody: fixtureData("getCommentsResponseV3"))
        let api = LemmyApi(
            instanceUrl: URL(string: "https://example.invalid")!,
            credential: nil,
            transport: transport,
            apiVersion: .v3
        )

        _ = try await api.getCommentsNeutral(postId: 180, sort: .hot)

        let path = await transport.capturedPath ?? ""
        XCTAssertTrue(path.contains("type_=All"), "expected type_=All in path, got: \(path)")
        XCTAssertTrue(path.contains("max_depth=15"), "expected max_depth=15 in path, got: \(path)")
        XCTAssertFalse(path.contains("limit="), "post-scoped fetch must not send limit, got: \(path)")
    }

    /// The v3 parent-scoped ("load more replies") fetch sends a full-size page.
    /// Without `limit` the server's default of 10 applies, so one tap on a
    /// 28-reply subtree returns 10 replies and immediately re-surfaces a
    /// frontier row. 50 is Lemmy's ceiling -- `limit=300` fails outright with
    /// `couldnt_get_comments`.
    func testGetCommentsNeutralByParentV3SendsPageLimit() async throws {
        let transport = try PathCapturingStubTransport(responseBody: fixtureData("getCommentsResponseV3"))
        let api = LemmyApi(
            instanceUrl: URL(string: "https://example.invalid")!,
            credential: nil,
            transport: transport,
            apiVersion: .v3
        )

        _ = try await api.getCommentsNeutral(parentId: 42, sort: .hot)

        let path = await transport.capturedPath ?? ""
        XCTAssertTrue(path.contains("type_=All"), "expected type_=All in path, got: \(path)")
        XCTAssertTrue(path.contains("parent_id=42"), "expected parent_id in path, got: \(path)")
        XCTAssertTrue(path.contains("limit=50"), "expected limit=50 in path, got: \(path)")
        XCTAssertFalse(path.contains("max_depth"), "parent-scoped fetch must not send max_depth, got: \(path)")
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /Users/denis/dev/info.ddenis/Spud/LemmyKit
swift test --filter "GetListNeutralTests/testGetCommentsNeutralV3SendsListingTypeAndMaxDepth" 2>&1 | tail -12
swift test --filter "GetListNeutralTests/testGetCommentsNeutralByParentV3SendsPageLimit" 2>&1 | tail -12
```

Expected: the first fails with `expected max_depth=15 in path, got: …max_depth=8…`; the second fails with `expected limit=50 in path`.

- [ ] **Step 3: Raise the depth constant**

In `Sources/LemmyKit/LemmyApi+GetCommentsNeutral.swift`, change the value returned by `postCommentTreeMaxDepth` from `8` to `15` and append this paragraph to its doc comment, immediately before the closing line about v4:

```swift
    /// 15 rather than something larger: the server caps the response at 300
    /// comments regardless of depth, so depth is nearly free (a 537-comment post
    /// measured 1,596,078 bytes at depth 8 and 1,608,548 at depth 20, both
    /// capped at 300) and a deeper request returns complete trees for ordinary
    /// posts -- a 135-comment post is complete from depth 12. 15 leaves headroom
    /// while staying modest in case an instance does not enforce that cap.
```

- [ ] **Step 4: Add the page-limit constant**

In the same `public extension LemmyApi` block, directly after `postCommentTreeMaxDepth`, add:

```swift
    /// Page size for the parent-scoped ("load more replies") comment fetch.
    ///
    /// Unlike the post-scoped fetch -- where `max_depth` makes the server ignore
    /// `limit` entirely -- the parent-scoped fetch IS bounded by `limit`, and
    /// with none sent the server's default of 10 applies: one tap on a 28-reply
    /// subtree returns 10 replies and immediately re-surfaces a frontier row.
    ///
    /// 50 is Lemmy's ceiling, not an arbitrary "large" value: `limit=300` fails
    /// outright with `{"error":"couldnt_get_comments"}`.
    static var commentListingPageLimit: Components.Parameters.Limit { 50 }
```

- [ ] **Step 5: Send the limit on the parent-scoped v3 request**

In the private `getCommentsNeutralV3(parentId:sort:)`, add the `limit` argument:

```swift
        let response = try await getComments(query: .init(
            type_: .All,
            sort: v3CommentSortType(fromNeutral: sort),
            limit: LemmyApi.commentListingPageLimit,
            parent_id: v3CommentID(parentId)
        ))
```

Then update that method's doc comment on the public `getCommentsNeutral(parentId:sort:pageCursor:)` — the line currently reading "and sends **no `max_depth`** -- the server's page `limit` is the only bound" becomes:

```swift
    /// Like the post-scoped fetch it sends v3's listing `type_` as `.All` (v4's as `.all`) so
    /// replies on remote/federated communities are not dropped, and sends **no `max_depth`** -- the
    /// page `limit` (``LemmyApi/commentListingPageLimit``) is the only bound. Any frontier the page
    /// cut off re-surfaces as a fresh "load more" placeholder downstream (driven by each comment's
    /// `childCount`).
```

- [ ] **Step 6: Run the full LemmyKit suite**

```bash
cd /Users/denis/dev/info.ddenis/Spud/LemmyKit
swift test 2>&1 | grep -E "Test Suite 'All tests'|Executed [0-9]+ tests|Test run with|error:" | tail -6
```

Expected: `Test Suite 'All tests' passed`, and the Swift Testing line `Test run with <N> tests in <M> suites passed`. Both must show zero failures.

- [ ] **Step 7: Format, commit and push LemmyKit**

SwiftFormat may reformat files this task did not touch. Revert any such file before staging.

```bash
cd /Users/denis/dev/info.ddenis/Spud/LemmyKit
mint run swiftformat Sources Tests
git status --short
# For any file listed that this task did not modify:
#   git checkout -- <that file>
git add Sources/LemmyKit/LemmyApi+GetCommentsNeutral.swift Tests/LemmyKitTests/GetListNeutralTests.swift
git commit -m "feat: deepen the post comment tree and send a full load-more page

The post-scoped fetch now requests max_depth=15 rather than 8. The server caps
the response at 300 comments regardless of depth, so depth costs almost nothing
(+0.8% payload on a 537-comment post) and buys complete trees on ordinary posts.

The parent-scoped 'load more replies' fetch now sends limit=50, Lemmy's ceiling.
With no limit the server's default of 10 applied, so one tap on a 28-reply
subtree returned 10 replies and immediately re-surfaced a frontier row.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
git push origin main
git rev-parse HEAD
```

- [ ] **Step 8: Bump the Spud pin and resolve**

Take the SHA printed by `git rev-parse HEAD` above and put it in `Spud/project.yml`, replacing the `revision:` value on line 37. Leave the surrounding comment about the untagged PieFed dialect intact — the pin stays a `revision:`, not a release tag.

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud
# edit project.yml: packages.LemmyKit.revision -> <new SHA>
make project
rm -f Spud.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
xcodebuild -resolvePackageDependencies -project Spud.xcodeproj 2>&1 | grep -i "lemmykit" | head -3
jq -r '.pins[] | select(.identity=="lemmykit") | .state.revision' Spud.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
```

Expected: the printed revision equals the new SHA.

- [ ] **Step 9: Verify the app still builds and commit the pin**

Run the test command template with `-only-testing:SpudDataKitTests`.

Expected: `✔ Test run with <N> tests in <M> suites passed`.

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud
git add project.yml
git commit -m "chore: bump LemmyKit pin for deeper comment tree and load-more page limit

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Paginate the comment fetch

`LemmyService.fetchComments` issues one request and drops `page.nextPage`. On v3 that is correct (v3 has no comment cursor). On v4 and PieFed the listing genuinely paginates, so today only page one is ever shown. Paginate: import page 1 immediately for a fast first paint, then keep fetching and re-import the accumulated set. Task 1 made that re-import safe.

**Files:**
- Create: `SpudDataKit/Services/Lemmy/CommentFetchCompletion.swift`
- Modify: `SpudDataKit/Services/Lemmy/LemmyService.swift:60` (protocol), `:1124-1171` (implementation)
- Modify: `SpudDataKit/Services/Offline/OfflineDownloadService.swift:913` (call site)
- Modify: `Spud/Scenes/PostDetail/Content/PostDetailViewModel.swift:268-271` (default closure seam)
- Test: `SpudDataKitTests/LemmyServiceCommentPaginationTests.swift` (create)

**Interfaces:**
- Consumes: `AppDatabase.upsertComments(...)` from Task 1 (safe to call more than once per fetch).
- Produces:
  - `public enum CommentFetchCompletion: Sendable, Equatable { case complete; case partial(PartialReason) }` with `public enum PartialReason: Sendable, Equatable { case pageBudgetExhausted; case pageFetchFailed }`
  - `LemmyServiceType.fetchComments(serverPostId:sortType:) async throws -> CommentFetchCompletion` (was `-> Void`)
  - `LemmyService.maxCommentPages: Int` = 10

- [ ] **Step 1: Create the completion type**

Create `SpudDataKit/Services/Lemmy/CommentFetchCompletion.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// How a post's comment fetch ended.
///
/// This is the ONLY honest source for "is the loaded tree complete". The post's
/// comment counter cannot answer it: the server's count and the number of rows
/// a listing returns legitimately differ (a 135-comment post returns 138 rows),
/// and deriving tree state from the counter is the reconciliation approach this
/// project already considered and rejected. Whether a pagination cursor was
/// still outstanding when the fetch stopped is known exactly, at the source.
public enum CommentFetchCompletion: Sendable, Equatable {
    /// The listing was exhausted -- every page the server offered was fetched.
    /// Always the outcome on a v3 backend, whose comment listing has no cursor.
    case complete

    /// The fetch stopped with pages still outstanding.
    case partial(PartialReason)

    public enum PartialReason: Sendable, Equatable {
        /// The page budget (``LemmyService/maxCommentPages``) ran out first.
        case pageBudgetExhausted
        /// A later page failed after at least one page had already been
        /// imported. The earlier pages are kept and stay on screen.
        case pageFetchFailed
    }
}
```

- [ ] **Step 2: Write the failing tests**

Create `SpudDataKitTests/LemmyServiceCommentPaginationTests.swift`. It reuses three helpers that already exist in `SpudDataKitTests/LemmyServiceSubtreeChildCountTests.swift`: the `SequencedCommentsTransport` actor (line 238), the `FailingCommentsTransport` class (line 271), and `SubtreeCommentsFixture.v4Page(commentId:childCount:nextPage:)`. All three are `private` to that file, so **first change those three declarations from `private` to internal** (delete the `private` keyword) in `LemmyServiceSubtreeChildCountTests.swift` so this new suite can use them — do not copy-paste duplicates.

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

/// `fetchComments` must walk the whole comment listing, not just page one.
/// v3 returns its tree in a single cursor-less response, but v4 and PieFed
/// listings paginate -- so fetching one page truncated the tree on those
/// dialects permanently.
@MainActor
struct LemmyServiceCommentPaginationTests {
    /// Number of comment element rows stored for the post, across all sorts.
    private func storedCommentCount(_ appDatabase: AppDatabase) async throws -> Int {
        try await appDatabase.writer.read { db in
            try CommentElementRecord
                .filter(Column("commentId") != nil)
                .fetchCount(db)
        }
    }

    /// A v4 listing spanning three pages is walked to the end.
    @Test
    func v4ListingIsWalkedToCompletion() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let transport = SequencedCommentsTransport(
            operationID: "GetComments",
            pages: [
                SubtreeCommentsFixture.v4Page(commentId: 501, childCount: 0, nextPage: "Pc2"),
                SubtreeCommentsFixture.v4Page(commentId: 502, childCount: 0, nextPage: "Pc3"),
                SubtreeCommentsFixture.v4Page(commentId: 503, childCount: 0, nextPage: nil),
            ]
        )
        let service = LemmyServiceHarness.make(
            accountKeychainId: "kc-comment-pagination-v4",
            appDatabase: appDatabase,
            transport: transport,
            apiVersion: .v4
        )

        let completion = try await service.fetchComments(serverPostId: 180, sortType: .Hot)

        #expect(completion == .complete)
        let callCount = await transport.callCount
        #expect(callCount == 3, "every page of the listing must be fetched")
    }

    /// A v3 listing has no cursor, so exactly one request is made and nothing
    /// about the existing behavior changes.
    @Test
    func v3ListingIssuesASingleRequest() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let transport = SequencedCommentsTransport(
            operationID: "getComments",
            pages: [SubtreeCommentsFixture.v3Page(commentId: 501, childCount: 0)]
        )
        let service = LemmyServiceHarness.make(
            accountKeychainId: "kc-comment-pagination-v3",
            appDatabase: appDatabase,
            transport: transport,
            apiVersion: .v3
        )

        let completion = try await service.fetchComments(serverPostId: 180, sortType: .Hot)

        #expect(completion == .complete)
        let callCount = await transport.callCount
        #expect(callCount == 1, "v3 has no comment cursor -- one request only")
    }

    /// Hitting the page budget reports `.partial(.pageBudgetExhausted)` rather
    /// than letting a truncated tree pass for whole. Every page here advertises
    /// another cursor, so without the bound this would loop forever.
    @Test
    func exhaustingThePageBudgetReportsPartial() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let endlessPages = (0..<(LemmyService.maxCommentPages + 2)).map { index in
            SubtreeCommentsFixture.v4Page(
                commentId: Int64(600 + index),
                childCount: 0,
                nextPage: "Pc\(index + 2)"
            )
        }
        let transport = SequencedCommentsTransport(operationID: "GetComments", pages: endlessPages)
        let service = LemmyServiceHarness.make(
            accountKeychainId: "kc-comment-pagination-budget",
            appDatabase: appDatabase,
            transport: transport,
            apiVersion: .v4
        )

        let completion = try await service.fetchComments(serverPostId: 180, sortType: .Hot)

        #expect(completion == .partial(.pageBudgetExhausted))
        let callCount = await transport.callCount
        #expect(callCount == LemmyService.maxCommentPages)
    }

    /// A failure on a later page keeps the pages that already arrived: it must
    /// not throw the whole fetch away, and it must not report `.complete`.
    @Test
    func laterPageFailureKeepsEarlierPages() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let transport = FailAfterFirstPageTransport(
            firstPage: SubtreeCommentsFixture.v4Page(commentId: 501, childCount: 0, nextPage: "Pc2")
        )
        let service = LemmyServiceHarness.make(
            accountKeychainId: "kc-comment-pagination-fail",
            appDatabase: appDatabase,
            transport: transport,
            apiVersion: .v4
        )

        let completion = try await service.fetchComments(serverPostId: 180, sortType: .Hot)

        #expect(completion == .partial(.pageFetchFailed))
        // Hoist the await out of #expect: SwiftFormat mangles `#expect(await …)`
        // into invalid syntax (`#expectawait(…)`).
        let kept = try await storedCommentCount(appDatabase)
        #expect(kept >= 1, "page 1 must survive page 2's failure")
    }

    /// A failure on the FIRST page still throws -- there is nothing to keep, and
    /// the caller needs to drive the inline failed state.
    @Test
    func firstPageFailureThrows() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let service = LemmyServiceHarness.make(
            accountKeychainId: "kc-comment-pagination-first-fail",
            appDatabase: appDatabase,
            transport: FailingCommentsTransport(),
            apiVersion: .v4
        )

        await #expect(throws: (any Error).self) {
            _ = try await service.fetchComments(serverPostId: 180, sortType: .Hot)
        }
    }
}

/// Serves one good page (advertising a next cursor) and then fails every
/// subsequent request with HTTP 500 -- the mid-pagination failure case.
private actor FailAfterFirstPageTransport: ClientTransport {
    private let firstPage: Data
    private(set) var callCount = 0

    init(firstPage: Data) {
        self.firstPage = firstPage
    }

    func send(
        _: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID _: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        callCount += 1
        if callCount == 1 {
            var response = HTTPResponse(status: .ok)
            response.headerFields[.contentType] = "application/json"
            return (response, HTTPBody(firstPage))
        }
        var response = HTTPResponse(status: .internalServerError)
        response.headerFields[.contentType] = "application/json"
        return (response, HTTPBody(Data(#"{"error":"internal_server_error"}"#.utf8)))
    }
}
```

`SubtreeCommentsFixture` already provides both builders — `v3Page(commentId:childCount:)` at line 26 and `v4Page(commentId:childCount:nextPage:)` at line 119 — so nothing new needs writing, only the `private` removed. Copy the `HTTPTypes` / `OpenAPIRuntime` import block from `LemmyServiceSubtreeChildCountTests.swift`; the custom transport below needs it.

**The post must be seeded.** `upsertComments` silently no-ops when the post row is missing, so `laterPageFailureKeepsEarlierPages` would assert 0 stored comments and fail for the wrong reason. Add the same `seed` helper Task 1 uses (copied from `SpliceMoreCommentsTests.swift:20-46`) to this suite, call it with `serverPostId: 180` at the top of **every** test here, and pass its `accountKeychainId` to `LemmyServiceHarness.make` so the service resolves the same account:

```swift
        let appDatabase = try AppDatabase.inMemory()
        _ = try await seed(appDatabase, serverPostId: 180)
```

Give the seed helper's `AccountRecord` the same `accountKeychainId` string each test passes to `LemmyServiceHarness.make` (the plan's per-test `kc-comment-pagination-*` values), rather than the fixed `"keychain-stable-identity"` Task 1 uses — take it as a parameter.

- [ ] **Step 3: Run the tests to verify they fail**

Run the test command template with `-only-testing:SpudDataKitTests/LemmyServiceCommentPaginationTests`.

Expected: `v4ListingIsWalkedToCompletion`, `exhaustingThePageBudgetReportsPartial` and `laterPageFailureKeepsEarlierPages` FAIL — `fetchComments` currently returns `Void` so the file will not even compile until Step 4 changes the signature. Treat the compile error as the failing state; do not proceed to Step 5 until Step 4 is done.

- [ ] **Step 4: Implement pagination**

In `SpudDataKit/Services/Lemmy/LemmyService.swift`, change the protocol declaration at line 60 from `async throws` to `async throws -> CommentFetchCompletion`, add the page-budget constant next to `maxSubtreeChildCountPages`, and replace the body of `fetchComments`:

```swift
    /// Bound on how many comment pages a single `fetchComments` walks before
    /// giving up and reporting `.partial(.pageBudgetExhausted)`. Mirrors
    /// ``maxSubtreeChildCountPages``.
    public static let maxCommentPages = 10

    public func fetchComments(
        serverPostId: Lemmy.PostID,
        sortType: Lemmy.CommentSortType
    ) async throws -> CommentFetchCompletion {
        logger.debug("""
            Fetch comments for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)). \
            postId=\(serverPostId, privacy: .public) \
            sortType=\(sortType.rawValue, privacy: .public)
            """)

        // Page 1 is fetched, imported and rendered before the rest of the
        // listing is walked: on a multi-page dialect (v4, PieFed) waiting for
        // the whole walk would leave the reader on a skeleton for several
        // serial round trips. Re-importing the accumulated set afterwards is
        // safe because `upsertComments` reconciles element rows in place.
        let firstPage: Page<Lemmy.CommentView>
        do {
            firstPage = try await api.getCommentsNeutral(
                postId: Int64(serverPostId),
                sort: sortType.neutralCommentSort
            )
        } catch {
            logger.error("""
                Fetch comments failed. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)). \
                postId=\(serverPostId, privacy: .public). \
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

        var collected = firstPage.items
        try await mirrorCommentsToAppDatabase(
            serverPostId: serverPostId,
            sortType: sortType,
            comments: collected
        )

        var completion: CommentFetchCompletion = .complete
        var pageCursor = firstPage.nextPage
        var pagesFetched = 1
        while let cursor = pageCursor {
            guard pagesFetched < Self.maxCommentPages else {
                completion = .partial(.pageBudgetExhausted)
                break
            }
            let page: Page<Lemmy.CommentView>
            do {
                page = try await api.getCommentsNeutral(
                    postId: Int64(serverPostId),
                    sort: sortType.neutralCommentSort,
                    pageCursor: cursor
                )
            } catch {
                // Earlier pages already landed and are on screen. Keep them and
                // report the shortfall rather than throwing the whole fetch away.
                logger.error("""
                    Fetch comments page failed, keeping earlier pages. \
                    account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)). \
                    postId=\(serverPostId, privacy: .public). \
                    \(String(describing: error), privacy: .public)
                    """)
                completion = .partial(.pageFetchFailed)
                break
            }
            pagesFetched += 1
            collected.append(contentsOf: page.items)
            pageCursor = page.nextPage
            try await mirrorCommentsToAppDatabase(
                serverPostId: serverPostId,
                sortType: sortType,
                comments: collected
            )
        }

        logger.debug("""
            Fetch comments for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            complete with \(collected.count, privacy: .public) comments \
            over \(pagesFetched, privacy: .public) page(s)
            """)

        // A removed comment carries no reason in the comment object -- fetch it
        // from the public modlog, but only when there's something to explain.
        if collected.contains(where: \.comment.removed) {
            await mirrorCommentRemovalReasons(serverPostId: serverPostId)
        }

        return completion
    }
```

Note: on v3 `firstPage.nextPage` is always nil, so the loop never runs and exactly one request is made — behavior is unchanged there.

- [ ] **Step 5: Fix the two call sites**

In `SpudDataKit/Services/Offline/OfflineDownloadService.swift:913`, prefix the call with `_ = `:

```swift
                _ = try await lemmyService.fetchComments(
```

In `Spud/Scenes/PostDetail/Content/PostDetailViewModel.swift:268-271`, the default closure is typed `@MainActor (Lemmy.CommentSortType) async throws -> Void`, so discard the result there for now (Task 4 changes this seam's type):

```swift
        self.fetchCommentsOperation = fetchCommentsOperation ?? { sortType in
            _ = try await dependencies.accountScope.lemmyService
                .fetchComments(serverPostId: serverPostId, sortType: sortType)
        }
```

Keep the surrounding closure body exactly as it is otherwise — read the current lines before editing rather than retyping them from this plan.

- [ ] **Step 6: Run the tests to verify they pass**

Run the test command template with `-only-testing:SpudDataKitTests/LemmyServiceCommentPaginationTests`.

Expected: all five tests PASS.

- [ ] **Step 7: Run the whole data-layer suite**

Run the test command template with `-only-testing:SpudDataKitTests`.

Expected: `✔ Test run with <N> tests in <M> suites passed`.

- [ ] **Step 8: Format and commit**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud
mint run swiftformat SpudDataKit/Services/Lemmy SpudDataKit/Services/Offline/OfflineDownloadService.swift Spud/Scenes/PostDetail/Content/PostDetailViewModel.swift SpudDataKitTests/LemmyServiceCommentPaginationTests.swift
git add SpudDataKit/Services/Lemmy/CommentFetchCompletion.swift SpudDataKit/Services/Lemmy/LemmyService.swift SpudDataKit/Services/Offline/OfflineDownloadService.swift Spud/Scenes/PostDetail/Content/PostDetailViewModel.swift SpudDataKitTests/LemmyServiceCommentPaginationTests.swift
git commit -m "feat: walk the whole comment listing, not just page one

fetchComments issued a single request and discarded page.nextPage. v3 returns
its tree in one cursor-less response so nothing changes there, but v4 and PieFed
comment listings paginate - on those dialects the tree was truncated at page one
permanently.

Page 1 is imported immediately so the tree paints after one round trip, then the
remaining pages are walked and the accumulated set re-imported (safe now that
element rows reconcile in place). The walk is bounded at maxCommentPages, and a
failure on a later page keeps the pages that already arrived. Both shortfalls
are reported as CommentFetchCompletion.partial rather than passing for whole.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Terminal "Load more comments" row

When pagination stops with a cursor outstanding, say so. The row is modelled in the view layer, not the database — no migration, and it follows the existing `Item.commentsEmpty` / `.commentsFailed` pattern exactly.

**Files:**
- Modify: `Spud/Scenes/PostDetail/Content/PostDetailViewModel.swift` (seam type, new state, new action)
- Modify: `Spud/Scenes/PostDetail/Content/PostDetailViewController.swift:2046-2053` (`Item`), `:917-961` (snapshot), `:2377` (selection)
- Test: `SpudTests/PostDetailPartialCommentLoadTests.swift` (create)

**Interfaces:**
- Consumes: `CommentFetchCompletion` from Task 3.
- Produces on `PostDetailViewModel`:
  - `private(set) var hasOutstandingCommentPages: Bool`
  - `func loadMoreCommentPages() async`
  - the seam becomes `@MainActor (Lemmy.CommentSortType) async throws -> CommentFetchCompletion`

- [ ] **Step 1: Write the failing test**

Create `SpudTests/PostDetailPartialCommentLoadTests.swift`. Build the view model exactly the way the existing `SpudTests/PostDetailViewModelObservationTests.swift` does — read it first and copy its construction helper, including `PreferencesService.ephemeral()`.

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudDataKit
import Testing
@testable import Spud

/// A comment fetch that stopped with pages outstanding must say so. The header
/// count cannot be used for this -- server counts and returned row counts
/// legitimately differ -- so the signal comes from the fetch's own completion.
@MainActor
struct PostDetailPartialCommentLoadTests {
    @Test
    func exhaustedPageBudgetMarksOutstandingPages() async throws {
        let vm = makeViewModel(completion: .partial(.pageBudgetExhausted))
        await vm.fetchComments()
        #expect(vm.hasOutstandingCommentPages)
    }

    @Test
    func completeFetchMarksNoOutstandingPages() async throws {
        let vm = makeViewModel(completion: .complete)
        await vm.fetchComments()
        #expect(!vm.hasOutstandingCommentPages)
    }

    /// A later-page failure is a shortfall, not an outstanding page the reader
    /// can tap to resume -- it must not raise the "load more" affordance.
    @Test
    func pageFetchFailureDoesNotMarkOutstandingPages() async throws {
        let vm = makeViewModel(completion: .partial(.pageFetchFailed))
        await vm.fetchComments()
        #expect(!vm.hasOutstandingCommentPages)
    }

    /// A fresh fetch (sort change, retry) clears a stale outstanding-pages flag.
    @Test
    func aCompleteRefetchClearsOutstandingPages() async throws {
        let completions: [CommentFetchCompletion] = [
            .partial(.pageBudgetExhausted),
            .complete,
        ]
        let vm = makeViewModel(completions: completions)
        await vm.fetchComments()
        #expect(vm.hasOutstandingCommentPages)
        await vm.fetchComments()
        #expect(!vm.hasOutstandingCommentPages)
    }
}
```

Add the `makeViewModel(completion:)` / `makeViewModel(completions:)` helpers to this file, injecting a `fetchCommentsOperation` closure that returns the queued completion values in order.

- [ ] **Step 2: Run the test to verify it fails**

Run the test command template with `-only-testing:SpudTests/PostDetailPartialCommentLoadTests`.

Expected: compile failure — `hasOutstandingCommentPages` does not exist and the seam still returns `Void`. That is the failing state.

- [ ] **Step 3: Widen the seam and add the state**

In `PostDetailViewModel.swift`:

Change the seam's stored-property type (line 176) and its initialiser parameter (line 259) from `-> Void` to `-> CommentFetchCompletion`, and drop the `_ = ` added in Task 3 Step 5 so the default closure returns the value:

```swift
    private let fetchCommentsOperation: @MainActor (Lemmy.CommentSortType) async throws -> CommentFetchCompletion
```

```swift
        fetchCommentsOperation: (@MainActor (Lemmy.CommentSortType) async throws -> CommentFetchCompletion)? = nil,
```

```swift
        self.fetchCommentsOperation = fetchCommentsOperation ?? { sortType in
            try await dependencies.accountScope.lemmyService
                .fetchComments(serverPostId: serverPostId, sortType: sortType)
        }
```

Add the observable state next to `commentFetchError`:

```swift
    /// True when the last comment fetch stopped with pages the reader can still
    /// ask for. Drives the terminal "Load more comments" row. Only
    /// `.pageBudgetExhausted` sets it: a failed page is a shortfall to report,
    /// not a cursor to resume from.
    private(set) var hasOutstandingCommentPages = false
```

In `fetchComments()`, capture the completion (the `try await fetchCommentsOperation(sortType)` call at line 645):

```swift
                let completion = try await fetchCommentsOperation(sortType)
                if !Task.isCancelled {
                    // A successful (winning) load clears any lingering failure so
                    // the empty / comments state can show.
                    commentFetchError = nil
                    hasOutstandingCommentPages = completion == .partial(.pageBudgetExhausted)
                }
```

Add the resume action next to `loadMoreReplies`:

```swift
    /// Resumes a comment listing that stopped at the page budget, from the
    /// terminal "Load more comments" row. Reuses the ordinary fetch path: the
    /// service walks another budget's worth of pages and reports whether any
    /// remain.
    func loadMoreCommentPages() async {
        await fetchComments()
    }
```

- [ ] **Step 4: Run the test to verify it passes**

Run the test command template with `-only-testing:SpudTests/PostDetailPartialCommentLoadTests`.

Expected: all four tests PASS.

- [ ] **Step 5: Add the row to the view controller**

In `PostDetailViewController.swift`, add a case to `Item` next to `commentsFailed` (around line 2052):

```swift
        /// Terminal row shown when the comment listing stopped with pages still
        /// outstanding. Tapping it resumes the walk.
        case commentsLoadMore
```

In the snapshot builder (around line 961, immediately after `snapshot.appendItems(sectionItems, toSection: .comments)`), append the row when there is something outstanding:

```swift
        if viewModel.hasOutstandingCommentPages {
            snapshot.appendItems([.commentsLoadMore], toSection: .comments)
        }
```

Add a cell case to the data source's cell provider, immediately after the `case .commentsFailed:` branch (around line 2188), following the exact dequeue pattern its neighbours use:

```swift
            case .commentsLoadMore:
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: PostDetailLoadMoreCommentsCell.reuseIdentifier,
                    for: indexPath
                ) as! PostDetailLoadMoreCommentsCell
                cell.setLoading(viewModel.isLoadingComments)
                return cell
```

Create `Spud/Scenes/PostDetail/Content/Comment/PostDetailLoadMoreCommentsCell.swift` modelled on the existing `PostDetailEmptyCommentsCell` (same file directory, same `reuseIdentifier` + `register` convention — register it next to where `PostDetailCommentsFailedCell` is registered). Requirements:

- Label text: "Load more comments", using the same link-like styling the "N more replies" row uses.
- `accessibilityTraits = .button`, `accessibilityHint = NSLocalizedString("Loads more comments", comment: …)`.
- `setLoading(_:)` swaps the label for an inline spinner, matching how the "N more replies" row shows its in-flight state.
- Dynamic Type and light/dark must both work — inherit from the sibling cell rather than hard-coding a font or colour.

In `tableView(_:didSelectRowAt:)` (around line 2377), handle the tap:

```swift
        if dataSource.itemIdentifier(for: indexPath) == .commentsLoadMore {
            tableView.deselectRow(at: indexPath, animated: true)
            Task { [weak self] in await self?.viewModel.loadMoreCommentPages() }
            return
        }
```

- [ ] **Step 6: Regenerate the project and run the app-level suite**

`PostDetailLoadMoreCommentsCell.swift` is a new source file, so XcodeGen must pick it up or the build fails with "Cannot find PostDetailLoadMoreCommentsCell in scope" for a file that exists on disk:

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud
make project
```

- [ ] **Step 7: Build and run the app-level suite**

Run the test command template with `-only-testing:SpudTests`.

Expected: `✔ Test run with <N> tests in <M> suites passed`. If suites named `DMThreadViewModelLoadOlderTests`, `CommunityViewModelTests`, `PostListViewModel*Tests`, `SubscriptionsNotifyViewModelTests` or `PostDetailViewModelObservationTests` report failures, re-run **only those classes** in isolation before treating them as real — they are a known Swift Testing parallelism flake in this project and pass on their own.

- [ ] **Step 8: Format and commit**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud
mint run swiftformat Spud/Scenes/PostDetail SpudTests/PostDetailPartialCommentLoadTests.swift
git add Spud/Scenes/PostDetail/Content/PostDetailViewModel.swift Spud/Scenes/PostDetail/Content/PostDetailViewController.swift Spud/Scenes/PostDetail/Content/Comment/PostDetailLoadMoreCommentsCell.swift SpudTests/PostDetailPartialCommentLoadTests.swift project.yml
git commit -m "feat: terminal 'Load more comments' row when pages remain

A comment listing that stops at the page budget no longer passes for complete.
The view model tracks the fetch's own completion - not the header's comment
count, which legitimately differs from the row count - and post detail appends a
tappable terminal row that resumes the walk.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Keep what arrived when a later page fails

`CommentsBackground.decide` already suppresses the failed state whenever comments are on screen, so a mid-pagination failure currently produces silence: rows are shown and nothing says a page is missing. Surface it the way a load-more failure already is — a toast.

**Files:**
- Modify: `Spud/Scenes/PostDetail/Content/PostDetailViewModel.swift`
- Modify: `Spud/Scenes/PostDetail/Content/PostDetailViewController.swift:454`, `:525`, `:1192`, `:2200`
- Test: `SpudTests/PostDetailPartialCommentLoadTests.swift` (extend)

**Interfaces:**
- Consumes: `CommentFetchCompletion` (Task 3), `hasOutstandingCommentPages` (Task 4).
- Produces on `PostDetailViewModel`: `func consumePartialCommentLoadFailure() -> Bool` — returns `true` once after a fetch ended `.partial(.pageFetchFailed)`, and clears the flag.

- [ ] **Step 1: Write the failing test**

Append to `SpudTests/PostDetailPartialCommentLoadTests.swift`:

```swift
    /// A later-page failure is reported exactly once, so a re-render cannot
    /// re-toast it.
    @Test
    func partialFailureIsConsumedOnce() async throws {
        let vm = makeViewModel(completion: .partial(.pageFetchFailed))
        await vm.fetchComments()
        #expect(vm.consumePartialCommentLoadFailure())
        #expect(!vm.consumePartialCommentLoadFailure())
    }

    /// A complete fetch reports nothing.
    @Test
    func completeFetchHasNoPartialFailureToConsume() async throws {
        let vm = makeViewModel(completion: .complete)
        await vm.fetchComments()
        #expect(!vm.consumePartialCommentLoadFailure())
    }

    /// A mid-pagination failure must NOT drive the inline failed state -- the
    /// pages that arrived stay on screen.
    @Test
    func partialFailureLeavesNoInlineFetchError() async throws {
        let vm = makeViewModel(completion: .partial(.pageFetchFailed))
        await vm.fetchComments()
        #expect(vm.commentFetchError == nil)
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run the test command template with `-only-testing:SpudTests/PostDetailPartialCommentLoadTests`.

Expected: compile failure — `consumePartialCommentLoadFailure` does not exist.

- [ ] **Step 3: Implement the one-shot flag**

In `PostDetailViewModel.swift`, next to `hasOutstandingCommentPages`:

```swift
    /// Set when a fetch ended `.partial(.pageFetchFailed)` -- some pages landed
    /// and a later one did not. Read-and-clear via
    /// ``consumePartialCommentLoadFailure()`` so a re-render cannot re-toast it.
    private var pendingPartialCommentLoadFailure = false

    /// Returns `true` once after a comment fetch kept earlier pages but lost a
    /// later one, then clears. The view controller turns this into a toast: the
    /// inline failed state is wrong here because comments ARE on screen.
    func consumePartialCommentLoadFailure() -> Bool {
        defer { pendingPartialCommentLoadFailure = false }
        return pendingPartialCommentLoadFailure
    }
```

Extend the success branch in `fetchComments()` from Task 4:

```swift
                let completion = try await fetchCommentsOperation(sortType)
                if !Task.isCancelled {
                    // A successful (winning) load clears any lingering failure so
                    // the empty / comments state can show.
                    commentFetchError = nil
                    hasOutstandingCommentPages = completion == .partial(.pageBudgetExhausted)
                    pendingPartialCommentLoadFailure = completion == .partial(.pageFetchFailed)
                }
```

- [ ] **Step 4: Run the test to verify it passes**

Run the test command template with `-only-testing:SpudTests/PostDetailPartialCommentLoadTests`.

Expected: all seven tests PASS.

- [ ] **Step 5: Show the toast**

In `PostDetailViewController.swift`, add a toast helper beside `showLoadMoreFailureToast()` (line 1192), copying that method's presentation verbatim and changing only the message to "Some comments couldn't be loaded":

```swift
    /// Shown when a comment fetch kept the pages that arrived but lost a later
    /// one. A toast rather than the inline failed state: comments ARE on screen,
    /// and `CommentsBackground.decide` correctly suppresses `.failed` in that
    /// case, so without this the shortfall would be entirely silent.
    private func showPartialCommentLoadToast() {
        guard let window = view.window else { return }
        ToastPresenter.shared.show(
            NSLocalizedString(
                "Some comments couldn't be loaded",
                comment: "Toast when part of a post's comment listing fails to load"
            ),
            in: window
        )
    }
```

Then, at each of the four `await viewModel.fetchComments()` sites (lines 454, 525, 2200, and the `reloadAsync` path), follow the await with:

```swift
                if viewModel.consumePartialCommentLoadFailure() {
                    showPartialCommentLoadToast()
                }
```

- [ ] **Step 6: Run the app-level suite**

Run the test command template with `-only-testing:SpudTests`. Apply the same parallelism-flake rule as Task 4 Step 6.

- [ ] **Step 7: Format and commit**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud
mint run swiftformat Spud/Scenes/PostDetail SpudTests/PostDetailPartialCommentLoadTests.swift
git add Spud/Scenes/PostDetail/Content/PostDetailViewModel.swift Spud/Scenes/PostDetail/Content/PostDetailViewController.swift SpudTests/PostDetailPartialCommentLoadTests.swift
git commit -m "feat: surface a mid-pagination comment failure as a toast

A later page failing used to throw the whole fetch away. It now keeps the pages
that landed - and because CommentsBackground suppresses the inline failed state
whenever comments are on screen, that shortfall would otherwise be completely
silent. It is reported once, as a toast, matching how a load-more-replies
failure is already surfaced.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Documentation and full verification

**Files:**
- Modify: `docs/features/post-detail-and-comments.md`
- Modify: `docs/features/README.md` (capability table **and** "Feature coverage by area" map — they drift independently)
- Modify: `CLAUDE.md` (the neutral-wire-shapes bullet)

- [ ] **Step 1: Update the feature doc**

In `docs/features/post-detail-and-comments.md`, extend the "Opening a post loads the whole comment tree down to a depth cutoff" rule to state the new depth behavior, and add rules covering the two new states. Then add matching Given/When/Then scenarios in the Scenarios section:

```markdown
### A very large thread offers to load the rest

- **Given** a post whose comment listing is longer than a single load can walk
- **When** the tree finishes loading
- **Then** a "Load more comments" row appears at the end of the tree
- **And** tapping it continues loading from where it stopped

### A comment page that fails mid-load keeps what arrived

- **Given** a post whose comments load across several pages
- **When** a later page fails
- **Then** the comments that already loaded stay on screen
- **And** a "Some comments couldn't be loaded" toast appears
- **And** the tree does not fall back to the "couldn't load comments" placeholder
```

- [ ] **Step 2: Update both README index sections**

Both the capability table and the by-area map in `docs/features/README.md` must stay consistent. If the `ddenis:feature-docs` skill's `audit_feature_docs.py` is available, run it and fix whatever it reports.

- [ ] **Step 3: Update CLAUDE.md**

Update the bullet beginning "**SpudDataKit now consumes LemmyKit's version-neutral `*Neutral` API**" so the recorded wire shape matches: post-scoped sends `max_depth=15` and no `limit`; parent-scoped sends `limit=50` and no `max_depth`. **Another agent has uncommitted edits in this file** — check `git diff CLAUDE.md` before staging and commit only your own hunk (`git diff CLAUDE.md > /tmp/p.patch`, filter to your hunk, `git apply --cached`).

- [ ] **Step 4: Full verification**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud
mint run swiftformat .
git status --short
```

Revert any file SwiftFormat touched that this plan did not modify. Then run every unit-test target:

Run the test command template four times, with `-only-testing:SpudDataKitTests`, `-only-testing:SpudTests`, `-only-testing:SpudUtilKitTests`, `-only-testing:SpudUIKitTests`.

Expected: `✔ Test run with <N> tests in <M> suites passed` for each. Apply the parallelism-flake rule for `SpudTests`.

- [ ] **Step 5: Commit**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud
git add docs/features/post-detail-and-comments.md docs/features/README.md CLAUDE.md
git commit -m "docs: comment fetching completeness behavior and wire shapes

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 6: Report what was not verified**

State plainly in the final summary: the UITest targets were not run (they need a single booted simulator and this checkout is shared), and no on-device verification against a real v4 or PieFed server was performed — the pagination paths are covered by stub-transport tests only. Do not claim otherwise.

---

## Notes for the executor

- **Task 2 pushes to a remote and moves a shared pin.** Do not run it speculatively.
- **Do not add `limit` to the post-scoped fetch.** With `max_depth` set the server ignores it; sending it would be a lie in the request.
- **`spliceMoreComments` is not part of this work.** It already inserts in place. Leave it alone beyond keeping placeholder reconciliation consistent.
- If any task's tests cannot be made to pass in three attempts, stop and report rather than reshaping the design.
