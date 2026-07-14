# Load More Replies Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the "N more replies" placeholder row on post detail work — tapping it fetches the missing comment subtree and splices it into the tree in place (inline expansion), on both v3 and v4 Lemmy servers.

**Architecture:** A new version-neutral `getCommentsNeutral(parentId:sort:pageCursor:)` in LemmyKit fetches a comment subtree; a new `LemmyService.fetchMoreComments` accumulates the whole subtree (paginating on v4, single-page on v3) and hands it to a new additive `AppDatabase.spliceMoreComments` importer that inserts the descendants at the placeholder's position without the destructive whole-tree rebuild. The tap is wired through the existing `PostDetailCommentCell` gesture recognizer → a `PostDetailViewModel.loadMoreReplies` seam; the GRDB observation re-renders the expanded tree.

**Tech Stack:** Swift 6 (strict concurrency), UIKit, GRDB, LemmyKit (remote SPM package, dev checkout at `/Users/denis/dev/info.ddenis/Spud/LemmyKit`), Swift Testing (Spud unit tests), XCTest (LemmyKit tests).

## Global Constraints

- **Design spec:** `docs/superpowers/specs/2026-07-14-load-more-replies-design.md` (this repo). Read it first.
- **Two repos.** LemmyKit changes live in `/Users/denis/dev/info.ddenis/Spud/LemmyKit` (its own git repo). Spud changes live in this worktree: `/Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/load-more-replies` on branch `feat/load-more-replies`.
- **LemmyKit is a remote `revision:` pin.** During development, point `project.yml`'s LemmyKit package at the local dev checkout via `path:` (leave **uncommitted** — stage only code, never `project.yml`), and force a clean resolve so the local path wins. Restore + bump the committed `revision:` pin as the **FINAL** step (Task 7), and only after the LemmyKit commit is pushed. Keep it a `revision:` (not a release tag) — this work is unvalidated against a real 1.0 server.
- **Consume the neutral API.** Spud calls LemmyKit's `*Neutral` surface only — never the legacy v3-only `getComments(parentID:)`.
- **Swift Testing for Spud unit tests** (`import Testing`, `struct` suites, `@Test`, `#expect`/`#require`; `import Foundation` explicitly). LemmyKit tests are **XCTest**.
- **Strict concurrency (Swift 6).** `LemmyService` is an `actor`; `PostDetailViewModel` / cells are `@MainActor`.
- **No emojis** in code, comments, docs, or commit messages. Conventional commit subjects (`feat:`/`fix:`/`docs:`/`test:`). Small focused commits. Every commit message ends with the two trailer lines used by this session (Co-Authored-By + Claude-Session).
- **Run SwiftFormat before the final verify:** `mint run swiftformat <changed paths>` (the pre-commit hook blocks on violations).
- **Stage explicit paths, never `git add -A`** (annex snapshot refs + `.remember/` must stay out).
- **Docs are part of done** (Task 6): the per-capability doc under `docs/features/` + the README capability table + the by-area map.
- **Snapshot device:** iPhone 17 Pro / portrait / iOS 26.3.x (`make snapshot`). A live `UIActivityIndicatorView` is non-deterministic, so the loading state is **not** snapshot-tested (called out in Task 5).

### One-time worktree setup (run once before Task 2)

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/load-more-replies
make project     # generate the gitignored Spud.xcodeproj (XcodeGen)
```

---

### Task 1: LemmyKit — neutral `getCommentsNeutral(parentId:sort:pageCursor:)`

**Repo:** `/Users/denis/dev/info.ddenis/Spud/LemmyKit` (NOT the Spud worktree).

**Files:**
- Modify: `Sources/LemmyKit/LemmyApi+GetCommentsNeutral.swift`
- Possibly modify: the file defining `v3PostID(_:)` (add a sibling `v3CommentID(_:)` if none exists — grep first)
- Test: `Tests/LemmyKitTests/GetListNeutralTests.swift`

**Interfaces:**
- Produces: `func getCommentsNeutral(parentId: Int64, sort: CommentSort, pageCursor: Cursor? = nil) async throws -> Page<CommentView>` on `public extension LemmyApi`.

- [ ] **Step 1: Add the failing tests** (append inside `final class GetListNeutralTests`, after the existing `getCommentsNeutral` tests):

```swift
    // MARK: getCommentsNeutral(parentId:)

    func testGetCommentsNeutralByParentV4ForwardsParentId() async throws {
        let transport = try PathCapturingStubTransport(responseBody: fixtureData("getCommentsResponseV4"))
        let api = LemmyApi(
            instanceUrl: URL(string: "https://example.invalid")!,
            credential: nil,
            transport: transport,
            apiVersion: .v4
        )

        let page = try await api.getCommentsNeutral(parentId: 42, sort: .hot)

        let path = await transport.capturedPath ?? ""
        XCTAssertTrue(path.contains("parent_id=42"), "expected parent_id in path, got: \(path)")
        // Decodes and maps the same v4 fixture the post-scoped test uses.
        XCTAssertEqual(page.items.map(\.comment.id), [501])
    }

    func testGetCommentsNeutralByParentV3ForwardsParentIdAndHasNoCursor() async throws {
        let transport = try PathCapturingStubTransport(responseBody: fixtureData("getCommentsResponseV3"))
        let api = LemmyApi(
            instanceUrl: URL(string: "https://example.invalid")!,
            credential: nil,
            transport: transport,
            apiVersion: .v3
        )

        let page = try await api.getCommentsNeutral(parentId: 42, sort: .hot)

        let path = await transport.capturedPath ?? ""
        XCTAssertTrue(path.contains("parent_id=42"), "expected parent_id in path, got: \(path)")
        // v3 comment listings carry no cursor at all.
        XCTAssertNil(page.nextPage)
        XCTAssertNil(page.prevPage)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd /Users/denis/dev/info.ddenis/Spud/LemmyKit && swift test --filter GetListNeutralTests`
Expected: FAIL — `getCommentsNeutral(parentId:...)` does not exist (compile error).

- [ ] **Step 3: Add the public method** to `Sources/LemmyKit/LemmyApi+GetCommentsNeutral.swift`, inside the existing `public extension LemmyApi` block (after the `postId:` overload):

```swift
    /// Fetches a comment SUBTREE — a parent comment and its descendants — and returns the
    /// version-neutral, cursor-paginated ``Page`` of ``CommentView``. This is the "load more
    /// replies" fetch: it mirrors ``getCommentsNeutral(postId:sort:pageCursor:)`` but scopes by
    /// parent comment id instead of post id.
    ///
    /// Like the post-scoped fetch it sends v3's listing `type_` as `.All` (v4's as `.all`) so
    /// replies on remote/federated communities are not dropped, and sends **no `max_depth`** — the
    /// server's page `limit` is the only bound. Any frontier the page cut off re-surfaces as a
    /// fresh "load more" placeholder downstream (driven by each comment's `childCount`).
    ///
    /// - Parameters:
    ///   - parentId: the parent comment whose descendant subtree to fetch.
    ///   - sort: the sort order to apply.
    ///   - pageCursor: opaque cursor from a previous page's `nextPage`; nil fetches the first page.
    ///     **v3 has no comment cursor** — on a v3-backed instance it is ignored and the returned
    ///     `Page` always has `nextPage`/`prevPage` nil (the whole subtree comes in one response).
    /// - Returns: a `Page` of neutral `CommentView`s in the subtree (may include the parent itself).
    func getCommentsNeutral(
        parentId: Int64,
        sort: CommentSort,
        pageCursor: Cursor? = nil
    ) async throws -> Page<CommentView> {
        switch apiVersion {
        case .v3:
            try await getCommentsNeutralV3(parentId: parentId, sort: sort)
        case .v4:
            try await getCommentsNeutralV4(parentId: parentId, sort: sort, pageCursor: pageCursor)
        }
    }
```

- [ ] **Step 4: Add the private v3/v4 paths** to the `private extension LemmyApi` block in the same file (next to the existing `getCommentsNeutralV3`/`V4`):

```swift
    /// v3 path for a parent-scoped fetch: reuses the shared `getComments(query:)` transport helper
    /// with `parent_id` set, then maps up to the neutral shape. v3 has no comment cursor, so this
    /// always returns a single, complete `Page` (`nextPage`/`prevPage` nil).
    func getCommentsNeutralV3(parentId: Int64, sort: CommentSort) async throws -> Page<CommentView> {
        let response = try await getComments(query: .init(
            type_: .All,
            sort: v3CommentSortType(fromNeutral: sort),
            parent_id: v3CommentID(parentId)
        ))

        return neutralPage(fromV3: response.comments, nextPage: nil) {
            neutralCommentView(fromV3: $0)
        }
    }

    /// v4 path for a parent-scoped fetch: calls the v4 client's `GetComments` with `parent_id` and
    /// the (optional) cursor, then maps near-directly to the neutral shape.
    func getCommentsNeutralV4(
        parentId: Int64,
        sort: CommentSort,
        pageCursor: Cursor?
    ) async throws -> Page<CommentView> {
        let response: LemmyKitV4Generated.Operations.GetComments.Output
        do {
            response = try await v4Client.GetComments(query: .init(
                parent_id: parentId,
                page_cursor: pageCursor?.rawValue,
                sort: v4CommentSortType(fromNeutral: sort),
                type_: .all
            ))
        } catch {
            throw LemmyApiError(from: error)
        }

        switch response {
        case let .ok(response):
            switch response.body {
            case let .json(json):
                return neutralPage(fromV4: json) { neutralCommentView(fromV4: $0) }
            }

        case let .undocumented(statusCode, _):
            throw LemmyApiError.unknownServerError(httpStatusCode: statusCode, error: nil)
        }
    }
```

- [ ] **Step 4a: Ensure `v3CommentID(_:)` exists.** Run `grep -rn "func v3PostID" Sources/LemmyKit` to find the narrowing helper, then `grep -rn "func v3CommentID" Sources/LemmyKit`. If `v3CommentID` does NOT exist, add it right next to `v3PostID` in the same file, matching `v3PostID`'s exact throwing narrowing pattern but returning `Components.Schemas.CommentID` from an `Int64`. (v3's `parent_id` is `Components.Schemas.CommentID`, an `Int32`; v4's is `Int64`, so no v4 helper is needed.)

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd /Users/denis/dev/info.ddenis/Spud/LemmyKit && swift test --filter GetListNeutralTests`
Expected: PASS — look for `Test Suite 'GetListNeutralTests' passed` / `Executed N tests`.

- [ ] **Step 6: Format and commit** (in the LemmyKit repo)

```bash
cd /Users/denis/dev/info.ddenis/Spud/LemmyKit
mint run swiftformat Sources Tests
git add Sources/LemmyKit/LemmyApi+GetCommentsNeutral.swift Tests/LemmyKitTests/GetListNeutralTests.swift
# also stage the v3CommentID file if you added one
git commit -m "feat: neutral getCommentsNeutral(parentId:) for load-more-replies

Adds a version-neutral parent-scoped comment fetch (v3 parent_id, v4
parent_id + cursor) mirroring the post-scoped getCommentsNeutral, for
loading a comment subtree on demand.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011EaJJgwwrWu2oxRdkAZtFY"
```

Do NOT push yet (push is gated in Task 7).

---

### Task 2: Spud — `AppDatabase.spliceMoreComments` importer

**Repo:** the Spud worktree. This task needs NO LemmyKit API change (it builds against the current pinned LemmyKit).

**Files:**
- Modify: `SpudDataKit/Services/AppDatabase/Importers/CommentImporter.swift` (add the method in the same `public extension AppDatabase` so it can call the `private static upsertComment(...in:)` helper)
- Test: `SpudDataKitTests/AppDatabase/SpliceMoreCommentsTests.swift` (new)

**Interfaces:**
- Consumes: `LemmyCommentImportHelper.sort(comments:)`, `LemmyCommentImportHelper.findCommentsWithMissingChildren(_:)`, `CommentPath(path:).depth`, the private `static func upsertComment(from:accountId:postRowId:siteId:respectsPendingOutbox:in:) throws -> Int64`.
- Produces: `func spliceMoreComments(forServerPostId: Int64, accountId: Int64, siteId: Int64, sortType: Lemmy.CommentSortType, parentServerId: Int64, comments: [Lemmy.CommentView]) async throws` on `public extension AppDatabase`.

- [ ] **Step 1: Write the failing test** — create `SpudDataKitTests/AppDatabase/SpliceMoreCommentsTests.swift`:

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

@MainActor
struct SpliceMoreCommentsTests {
    /// Seeds instance/site/account/post and returns the ids needed to import comments.
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
                accountKeychainId: "keychain-1",
                isSignedOutAccountType: false
            )
            try account.insert(db)
            return (account.id!, site.id!)
        }
        let person = Person.fake
        let community = Community.fake
        let post = Post.fake(creator: person, community: community, id: serverPostId)
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

    @Test
    func spliceInsertsDescendantsAndRemovesPlaceholder() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let seeded = try await seed(appDatabase, serverPostId: 1)

        // Initial tree: one top-level comment (id 10) that claims 1 missing child.
        let parent = CommentView.fake(
            comment: .fake(id: 10, post: seeded.post, creator: seeded.person, parent: .root),
            creator: seeded.person, post: seeded.post, community: seeded.community, childCount: 1
        )
        try await appDatabase.upsertComments(
            forServerPostId: 1, accountId: seeded.accountId, siteId: seeded.siteId,
            sortType: .Hot, comments: [parent]
        )

        let before = try await elements(appDatabase, postRowId: seeded.postRowId)
        #expect(before.count == 2)
        #expect(before[0].commentId != nil)                 // the parent comment row
        #expect(before[1].commentId == nil)                 // the "load more" placeholder
        #expect(before[1].moreParentId == 10)

        // Fetched subtree: parent (now childCount 0) + its child (id 20, no children).
        let parentLoaded = CommentView.fake(
            comment: .fake(id: 10, post: seeded.post, creator: seeded.person, parent: .root),
            creator: seeded.person, post: seeded.post, community: seeded.community, childCount: 0
        )
        let child = CommentView.fake(
            comment: .fake(id: 20, post: seeded.post, creator: seeded.person, parent: CommentPath(path: "0.10")),
            creator: seeded.person, post: seeded.post, community: seeded.community, childCount: 0
        )
        try await appDatabase.spliceMoreComments(
            forServerPostId: 1, accountId: seeded.accountId, siteId: seeded.siteId,
            sortType: .Hot, parentServerId: 10, comments: [parentLoaded, child]
        )

        let after = try await elements(appDatabase, postRowId: seeded.postRowId)
        #expect(after.count == 2)                            // parent + child, placeholder gone
        #expect(after.allSatisfy { $0.commentId != nil })   // no placeholder rows
        #expect(after[0].depth == 1)                         // top-level comment (root "0" counts)
        #expect(after[1].depth == 2)                         // its child
        #expect(after.map(\.position) == [0, 1])            // dense, ordered
    }

    @Test
    func spliceRegeneratesFrontierPlaceholderForStillMissingChildren() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let seeded = try await seed(appDatabase, serverPostId: 1)

        let parent = CommentView.fake(
            comment: .fake(id: 10, post: seeded.post, creator: seeded.person, parent: .root),
            creator: seeded.person, post: seeded.post, community: seeded.community, childCount: 1
        )
        try await appDatabase.upsertComments(
            forServerPostId: 1, accountId: seeded.accountId, siteId: seeded.siteId,
            sortType: .Hot, comments: [parent]
        )

        // Child itself claims a missing grandchild (childCount 1) -> a fresh placeholder.
        let parentLoaded = CommentView.fake(
            comment: .fake(id: 10, post: seeded.post, creator: seeded.person, parent: .root),
            creator: seeded.person, post: seeded.post, community: seeded.community, childCount: 0
        )
        let child = CommentView.fake(
            comment: .fake(id: 20, post: seeded.post, creator: seeded.person, parent: CommentPath(path: "0.10")),
            creator: seeded.person, post: seeded.post, community: seeded.community, childCount: 1
        )
        try await appDatabase.spliceMoreComments(
            forServerPostId: 1, accountId: seeded.accountId, siteId: seeded.siteId,
            sortType: .Hot, parentServerId: 10, comments: [parentLoaded, child]
        )

        let after = try await elements(appDatabase, postRowId: seeded.postRowId)
        #expect(after.count == 3)                            // parent, child, new placeholder
        #expect(after[2].commentId == nil)
        #expect(after[2].moreParentId == 20)
        #expect(after[2].depth == 3)
        #expect(after.map(\.position) == [0, 1, 2])
    }

    @Test
    func spliceIsNoOpWhenPlaceholderAlreadyGone() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let seeded = try await seed(appDatabase, serverPostId: 1)

        // A complete single comment: no placeholder exists.
        let only = CommentView.fake(
            comment: .fake(id: 10, post: seeded.post, creator: seeded.person, parent: .root),
            creator: seeded.person, post: seeded.post, community: seeded.community, childCount: 0
        )
        try await appDatabase.upsertComments(
            forServerPostId: 1, accountId: seeded.accountId, siteId: seeded.siteId,
            sortType: .Hot, comments: [only]
        )
        let before = try await elements(appDatabase, postRowId: seeded.postRowId)
        #expect(before.count == 1)

        // Splicing for a parent with no placeholder must not change anything.
        let child = CommentView.fake(
            comment: .fake(id: 20, post: seeded.post, creator: seeded.person, parent: CommentPath(path: "0.10")),
            creator: seeded.person, post: seeded.post, community: seeded.community, childCount: 0
        )
        try await appDatabase.spliceMoreComments(
            forServerPostId: 1, accountId: seeded.accountId, siteId: seeded.siteId,
            sortType: .Hot, parentServerId: 10, comments: [only, child]
        )

        let after = try await elements(appDatabase, postRowId: seeded.postRowId)
        #expect(after.count == 1)                            // unchanged
    }
}
```

- [ ] **Step 2: Add the new file to the project and run to verify it fails**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/load-more-replies
make project
make test-only ONLY=SpudDataKitTests
```
Expected: FAIL — `spliceMoreComments` does not exist (compile error). (If `make test-only` misfires with a 0/0 target error, use the xcodebuild fallback from CLAUDE.md: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -only-testing:SpudDataKitTests -destination "$(scripts/resolve-test-destination.sh)" -skipPackagePluginValidation -skipMacroValidation test`.)

- [ ] **Step 3: Implement `spliceMoreComments`** — add to `CommentImporter.swift`, inside the existing `public extension AppDatabase`, after `upsertComments`:

```swift
    /// Splices a freshly-fetched comment SUBTREE (a "load more replies" parent and its
    /// descendants) into the existing stored comment tree for `(post, sortType)`, in place —
    /// WITHOUT the destructive whole-tree rebuild `upsertComments` performs.
    ///
    /// Locates the "load more" placeholder element for `parentServerId`, upserts the fetched
    /// comments, inserts element rows for the descendants at the placeholder's position (shifting
    /// the rows after it), removes the placeholder, and regenerates frontier "load more"
    /// placeholders for any still-missing deeper leaves (same `childCount`-driven rule as
    /// `upsertComments`).
    ///
    /// Idempotent: a no-op if the placeholder is already gone (a double tap, or a re-splice after
    /// the observation already updated the tree). Skips silently if the post is not yet mirrored.
    ///
    /// - Parameters:
    ///   - parentServerId: the server comment id of the parent whose replies were fetched.
    ///   - comments: the fetched subtree (may include the parent itself; it is not re-inserted as a
    ///     new element, only refreshed).
    func spliceMoreComments(
        forServerPostId serverPostId: Int64,
        accountId: Int64,
        siteId: Int64,
        sortType: Lemmy.CommentSortType,
        parentServerId: Int64,
        comments: [Lemmy.CommentView]
    ) async throws {
        guard !comments.isEmpty else { return }

        try await writer.write { db in
            guard
                let postRowId = try PostRecord
                .filter(Column("accountId") == accountId)
                .filter(Column("postId") == serverPostId)
                .fetchOne(db)?
                .id
            else {
                logger.debug("Skipping splice - post \(serverPostId, privacy: .public) not yet in AppDatabase")
                return
            }

            let sortTypeRaw = sortType.rawValue

            // Locate the placeholder for this parent. Absent => already loaded; no-op (idempotent).
            guard
                let placeholder = try CommentElementRecord
                .filter(Column("postId") == postRowId)
                .filter(Column("sortType") == sortTypeRaw)
                .filter(Column("commentId") == nil)
                .filter(Column("moreParentId") == parentServerId)
                .fetchOne(db)
            else {
                return
            }
            let placeholderPosition = placeholder.position

            // Thread the fetched subtree in flat display order, then drop the parent itself (it
            // already has an element) — matched by server id, so this is correct whether or not the
            // response echoes the parent.
            let ordered = LemmyCommentImportHelper.sort(comments: comments)
            let descendants = ordered.filter { Int64($0.comment.id) != parentServerId }

            let missingChildren: Set<Lemmy.CommentID> = Set(
                LemmyCommentImportHelper
                    .findCommentsWithMissingChildren(comments)
                    .map { Lemmy.CommentID($0.comment.id) }
            )

            // Refresh the parent's own row (childCount etc.) if it was echoed in the response.
            if let parentView = ordered.first(where: { Int64($0.comment.id) == parentServerId }) {
                _ = try Self.upsertComment(
                    from: parentView, accountId: accountId, postRowId: postRowId, siteId: siteId,
                    respectsPendingOutbox: true, in: db
                )
            }

            // Build the new element rows (each descendant, plus a frontier placeholder after any
            // descendant that still claims missing children), using absolute path depth.
            struct PendingElement {
                let commentId: Int64?
                let depth: Int64
                let moreChildCount: Int64?
                let moreParentId: Int64?
            }
            var pending: [PendingElement] = []
            for view in descendants {
                let depth = Int64(CommentPath(path: view.comment.path).depth)
                let commentRowId = try Self.upsertComment(
                    from: view, accountId: accountId, postRowId: postRowId, siteId: siteId,
                    respectsPendingOutbox: true, in: db
                )
                pending.append(PendingElement(commentId: commentRowId, depth: depth, moreChildCount: nil, moreParentId: nil))
                if missingChildren.contains(Lemmy.CommentID(view.comment.id)) {
                    pending.append(PendingElement(
                        commentId: nil,
                        depth: depth + 1,
                        moreChildCount: view.comment.childCount,
                        moreParentId: Int64(view.comment.id)
                    ))
                }
            }

            // Shift the rows after the placeholder to make room. The single placeholder is removed
            // and `count` new rows take positions [placeholderPosition ..< placeholderPosition + count],
            // so rows after it move by (count - 1). (count == 1 => no shift; count == 0 => -1, closing
            // the placeholder's gap.)
            let count = Int64(pending.count)
            if count != 1 {
                try db.execute(
                    sql: "UPDATE commentElement SET position = position + ? WHERE postId = ? AND sortType = ? AND position > ?",
                    arguments: [count - 1, postRowId, sortTypeRaw, placeholderPosition]
                )
            }

            try placeholder.delete(db)

            var position = placeholderPosition
            for element in pending {
                var record = CommentElementRecord(
                    postId: postRowId,
                    commentId: element.commentId,
                    position: position,
                    depth: element.depth,
                    sortType: sortTypeRaw,
                    moreChildCount: element.moreChildCount,
                    moreParentId: element.moreParentId
                )
                try record.insert(db)
                position += 1
            }
        }
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `make test-only ONLY=SpudDataKitTests` (or the xcodebuild fallback).
Expected: PASS — `✔ Test run with N tests ... passed`; the three `SpliceMoreCommentsTests` show `✔`.

- [ ] **Step 5: Format and commit**

```bash
mint run swiftformat SpudDataKit/Services/AppDatabase/Importers/CommentImporter.swift SpudDataKitTests/AppDatabase/SpliceMoreCommentsTests.swift
git add SpudDataKit/Services/AppDatabase/Importers/CommentImporter.swift SpudDataKitTests/AppDatabase/SpliceMoreCommentsTests.swift
git commit -m "feat: spliceMoreComments importer for inline reply expansion

Additive, in-place splice of a fetched comment subtree into the stored
tree: inserts descendants at the placeholder's position, renumbers, and
regenerates frontier placeholders. Idempotent; leaves the destructive
whole-tree upsertComments path untouched.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011EaJJgwwrWu2oxRdkAZtFY"
```

---

### Task 3: Spud — `LemmyService.fetchMoreComments` (+ LemmyKit local-path override)

**Files:**
- Modify (UNCOMMITTED, dev-only): `project.yml` — LemmyKit package → local `path:`
- Modify: `SpudDataKit/Services/Lemmy/LemmyService.swift`
- Modify: `SpudDataKit/Services/Lemmy/LemmyServiceType.swift` (the protocol; grep for the file that declares `func fetchComments(` in a protocol) and any test doubles conforming to it
- Test: `SpudDataKitTests/LemmyServiceFetchMoreCommentsTests.swift` (new)

**Interfaces:**
- Consumes: `LemmyApi.getCommentsNeutral(parentId:sort:pageCursor:)` (Task 1), `AppDatabase.spliceMoreComments(...)` (Task 2), `accountSiteIds()`, `Self.maxSubtreeChildCountPages`.
- Produces: `func fetchMoreComments(serverPostId: Lemmy.PostID, parentServerId: Int64, sortType: Lemmy.CommentSortType) async throws` on `LemmyService` and `LemmyServiceType`.

- [ ] **Step 1: Apply the LemmyKit local-path override** (uncommitted) so Spud builds against Task 1's dev checkout. Edit `project.yml`: under `packages.LemmyKit`, replace the `revision:` line (keep a note of its current value — you restore it in Task 7) with:

```yaml
  LemmyKit:
    url: https://github.com/shadone/LemmyKit
    path: /Users/denis/dev/info.ddenis/Spud/LemmyKit
```

Then regenerate and force a clean resolve so the local path wins over the stale remote pin:

```bash
make project
rm -f Spud.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
xcodebuild -resolvePackageDependencies -project Spud.xcodeproj -skipPackagePluginValidation -skipMacroValidation 2>&1 | grep -i lemmykit
```
Expected: the resolve prints `LemmyKit: /Users/denis/dev/info.ddenis/Spud/LemmyKit` (local path). Do NOT `git add project.yml`.

- [ ] **Step 2: Write the failing integration test** — create `SpudDataKitTests/LemmyServiceFetchMoreCommentsTests.swift`. It builds a `LemmyService` over a stub `ClientTransport` that returns a canned v3 comments response, seeds a post + placeholder, calls `fetchMoreComments`, and asserts the placeholder was spliced away. Mirror the transport/`LemmyService` construction in `SpudDataKitTests/LemmyServiceContentNotFoundTests.swift` (open it and copy its `LemmyApi(... transport:)` + `LemmyService(...)` setup).

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
struct LemmyServiceFetchMoreCommentsTests {
    @Test
    func fetchMoreComments_splicesFetchedSubtree() async throws {
        // 1. Seed account/site/post and an initial tree with a "load more" placeholder under
        //    comment id 10 (reuse the seeding from SpliceMoreCommentsTests: upsertComments with a
        //    single childCount==1 comment). Keep the AppDatabase instance to pass into LemmyService.
        //
        // 2. Build a stub ClientTransport returning a v3 GetCommentsResponse JSON whose `comments`
        //    array contains comment id 10 (path "0.10", child_count 0) AND comment id 20
        //    (path "0.10.20", child_count 0). Model the stub + LemmyApi(apiVersion: .v3) exactly on
        //    LemmyServiceContentNotFoundTests (which returns HTTP 400); here return HTTP 200 with the
        //    comments body. If decoding throws, cross-check required fields against the generated
        //    v3 Types.swift (see the SBT-fixture-completeness gotcha in CLAUDE.md) and add them.
        //
        // 3. Construct LemmyService(accountKeychainId: "keychain-1", accountIsSignedOut: false,
        //    appDatabase: <seeded>, api: <stub api>, reachability: <the test double used by the
        //    neighbouring tests>).
        //
        // 4. Act + assert:
        //    try await service.fetchMoreComments(serverPostId: 1, parentServerId: 10, sortType: .Hot)
        //    let elements = try await appDatabase.writer.read { db in
        //        try CommentElementRecord
        //            .filter(Column("postId") == postRowId)
        //            .filter(Column("sortType") == Lemmy.CommentSortType.Hot.rawValue)
        //            .order(Column("position"))
        //            .fetchAll(db)
        //    }
        //    #expect(elements.count == 2)                       // parent + child, placeholder gone
        //    #expect(elements.allSatisfy { $0.commentId != nil })
    }
}
```

Note: this is the one place a JSON fixture is required. If assembling a valid v3 response body proves heavy, copy `getCommentsResponseV3.json` from `LemmyKit/Tests/LemmyKitTests/Fixtures/` into the SpudDataKitTests bundle and edit the two comment ids/paths — do NOT leave the test as a stub; a passing test is the deliverable. The splice math itself is already proven by Task 2, so this test only needs to prove the service wires fetch → splice for one comment id.

- [ ] **Step 3: Run to verify it fails**

Run: `make test-only ONLY=SpudDataKitTests`
Expected: FAIL — `fetchMoreComments` does not exist.

- [ ] **Step 4: Add `fetchMoreComments` to `LemmyService.swift`** (near `fetchComments` / `fetchSubtreeChildCount`):

```swift
    /// Fetches the missing reply subtree under `parentServerId` (the "load more replies" action)
    /// and splices it into the stored comment tree in place via `AppDatabase.spliceMoreComments`.
    ///
    /// Accumulates the whole subtree, following `Page.nextPage` up to `maxSubtreeChildCountPages`
    /// pages. On a v4 (cursor-paginated) server this walks every page; on v3 the whole subtree
    /// comes in one response (`nextPage` nil) so the loop runs once. Unlike `fetchSubtreeChildCount`
    /// (best-effort, returns nil), this THROWS on failure — the UI drives a loading/error state and
    /// must distinguish success from failure.
    public func fetchMoreComments(
        serverPostId: Lemmy.PostID,
        parentServerId: Int64,
        sortType: Lemmy.CommentSortType
    ) async throws {
        logger.debug("""
            Fetch more comments for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)). \
            postId=\(serverPostId, privacy: .public) parentId=\(parentServerId, privacy: .public) \
            sortType=\(sortType.rawValue, privacy: .public)
            """)

        var pageCursor: LemmyKit.Cursor?
        var collected: [Lemmy.CommentView] = []
        for _ in 0..<Self.maxSubtreeChildCountPages {
            let page: Page<Lemmy.CommentView>
            do {
                page = try await api.getCommentsNeutral(
                    parentId: parentServerId,
                    sort: sortType.neutralCommentSort,
                    pageCursor: pageCursor
                )
            } catch {
                logger.error("""
                    Fetch more comments failed. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)). \
                    postId=\(serverPostId, privacy: .public) parentId=\(parentServerId, privacy: .public). \
                    \(String(describing: error), privacy: .public)
                    """)
                throw LemmyServiceError(from: error)
            }
            collected.append(contentsOf: page.items)
            guard let next = page.nextPage else { break }
            pageCursor = next
        }

        guard let (accountRowId, siteRowId) = try await accountSiteIds() else {
            throw LemmyServiceError.internalInconsistency(
                description: "fetchMoreComments: account/site not found for \(accountIdentifierForLogging)"
            )
        }
        try await appDatabase.spliceMoreComments(
            forServerPostId: Int64(serverPostId),
            accountId: accountRowId,
            siteId: siteRowId,
            sortType: sortType,
            parentServerId: parentServerId,
            comments: collected
        )
    }
```

- [ ] **Step 5: Add to the `LemmyServiceType` protocol** (find it with `grep -rn "func fetchComments(" SpudDataKit`), matching the `fetchComments` declaration style:

```swift
    func fetchMoreComments(
        serverPostId: Lemmy.PostID,
        parentServerId: Int64,
        sortType: Lemmy.CommentSortType
    ) async throws
```

Then `grep -rn ": LemmyServiceType" Spud SpudDataKit SpudTests SpudSnapshotTests` and add the method to every conforming test double / mock (a passthrough or an empty `throws` stub is fine — keep behavior identical for existing tests). A missing conformance surfaces as a **build error in the test targets**, so building `make test-only ONLY=SpudDataKitTests` catches them.

- [ ] **Step 6: Run to verify it passes**

Run: `make test-only ONLY=SpudDataKitTests`
Expected: PASS — the new `LemmyServiceFetchMoreCommentsTests` shows `✔`, and no other target fails to build.

- [ ] **Step 7: Format and commit** (do NOT stage `project.yml`):

```bash
mint run swiftformat SpudDataKit/Services/Lemmy/LemmyService.swift SpudDataKit/Services/Lemmy/LemmyServiceType.swift SpudDataKitTests/LemmyServiceFetchMoreCommentsTests.swift
git add SpudDataKit/Services/Lemmy/LemmyService.swift SpudDataKit/Services/Lemmy/LemmyServiceType.swift SpudDataKitTests/LemmyServiceFetchMoreCommentsTests.swift
# plus any test-double files you had to update
git commit -m "feat: LemmyService.fetchMoreComments subtree fetch + splice

Paginates the neutral parent-scoped comment fetch (bounded), then
splices the accumulated subtree into the stored tree. Throws on failure
so the UI can drive a loading/error state.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011EaJJgwwrWu2oxRdkAZtFY"
```

---

### Task 4: Spud — `PostDetailViewModel.loadMoreReplies` + loading state

**Files:**
- Modify: `Spud/Scenes/PostDetail/Content/PostDetailViewModel.swift`
- Test: `SpudTests/...` — mirror an existing `PostDetailViewModel` test that injects `fetchCommentsOperation` (grep `SpudTests` for `PostDetailViewModel` and `fetchCommentsOperation`)

**Interfaces:**
- Consumes: `accountScope.lemmyService.fetchMoreComments(...)` (Task 3), the existing `commentSortType`, `serverPostId`, `updateOrderedComments(_:)`.
- Produces on `PostDetailViewModel`:
  - `func isLoadingMore(elementId: Int64) -> Bool`
  - `func markLoadingMore(elementId: Int64)`
  - `func clearLoadingMore(elementId: Int64)`
  - `func loadMoreReplies(elementId: Int64, parentServerId: Int64) async throws`
  - injectable `fetchMoreCommentsOperation: (Int64, Lemmy.CommentSortType) async throws -> Void`

- [ ] **Step 1: Write the failing test.** In a new `SpudTests/PostDetailLoadMoreTests.swift` (or add to the existing PostDetail VM test file), construct a `PostDetailViewModel` the same way the existing VM tests do, injecting `fetchMoreCommentsOperation`:

```swift
    @Test @MainActor
    func loadMoreReplies_forwardsParentAndSort_andClearsFlagOnFailure() async {
        var captured: (parent: Int64, sort: Lemmy.CommentSortType)?
        let viewModel = makePostDetailViewModel(          // reuse the existing test factory
            fetchMoreCommentsOperation: { parent, sort in
                captured = (parent, sort)
                throw LemmyServiceError.internalInconsistency(description: "boom")
            }
        )

        viewModel.markLoadingMore(elementId: 7)
        #expect(viewModel.isLoadingMore(elementId: 7) == true)

        await #expect(throws: (any Error).self) {
            try await viewModel.loadMoreReplies(elementId: 7, parentServerId: 99)
        }
        #expect(captured?.parent == 99)
        #expect(captured?.sort == viewModel.commentSortType)
        // On failure the VC clears the flag; simulate the VC step and confirm it clears.
        viewModel.clearLoadingMore(elementId: 7)
        #expect(viewModel.isLoadingMore(elementId: 7) == false)
    }
```

If the existing PostDetail VM tests use a different construction (e.g. a `makePostDetailViewModel` helper), match it and thread the new `fetchMoreCommentsOperation` init parameter through that helper.

- [ ] **Step 2: Run to verify it fails**

Run: `make test-only ONLY=SpudTests`
Expected: FAIL — the new symbols don't exist.

- [ ] **Step 3: Add the loading state + method to `PostDetailViewModel.swift`.**

Add a stored property near the other per-row ephemeral state:
```swift
    /// Element ids of "load more" rows with a fetch in flight. Reconciled against the live tree in
    /// `updateOrderedComments` (a successful splice removes the placeholder element, so its id
    /// disappears and the flag auto-clears); a failure is cleared explicitly by the view controller.
    private(set) var loadingMoreElementIds: Set<Int64> = []
```

Add the injectable operation. Find the `init` where `fetchCommentsOperation` is assigned and add a sibling parameter + default:
```swift
        // in init's parameter list, next to `fetchCommentsOperation:`
        fetchMoreCommentsOperation: ((Int64, Lemmy.CommentSortType) async throws -> Void)? = nil,
```
```swift
        // in init's body, next to the fetchCommentsOperation assignment
        self.fetchMoreCommentsOperation = fetchMoreCommentsOperation ?? { parentServerId, sortType in
            try await accountScope.lemmyService.fetchMoreComments(
                serverPostId: serverPostId,
                parentServerId: parentServerId,
                sortType: sortType
            )
        }
```
And the stored closure (match how `fetchCommentsOperation` is declared, incl. `@ObservationIgnored` if that's how the neighbour is declared):
```swift
    @ObservationIgnored
    private let fetchMoreCommentsOperation: (Int64, Lemmy.CommentSortType) async throws -> Void
```

Add the methods:
```swift
    func isLoadingMore(elementId: Int64) -> Bool {
        loadingMoreElementIds.contains(elementId)
    }

    func markLoadingMore(elementId: Int64) {
        loadingMoreElementIds.insert(elementId)
    }

    func clearLoadingMore(elementId: Int64) {
        loadingMoreElementIds.remove(elementId)
    }

    /// Fetches and splices the missing replies under `parentServerId`. The caller (the view
    /// controller) marks the row loading and reconfigures the cell before calling this, and on a
    /// thrown error clears the flag + reconfigures + shows a toast. On success the comment
    /// observation emits the spliced tree and the row is replaced.
    func loadMoreReplies(elementId: Int64, parentServerId: Int64) async throws {
        try await fetchMoreCommentsOperation(parentServerId, commentSortType)
    }
```

Add the reconciliation line inside `updateOrderedComments(_:)`, next to the existing `collapsedElementIds.formIntersection(existingIds)`:
```swift
        loadingMoreElementIds.formIntersection(existingIds)
```

- [ ] **Step 4: Run to verify it passes**

Run: `make test-only ONLY=SpudTests`
Expected: PASS — the new test shows `✔`.

- [ ] **Step 5: Format and commit**

```bash
mint run swiftformat Spud/Scenes/PostDetail/Content/PostDetailViewModel.swift SpudTests/PostDetailLoadMoreTests.swift
git add Spud/Scenes/PostDetail/Content/PostDetailViewModel.swift SpudTests/PostDetailLoadMoreTests.swift
git commit -m "feat: PostDetailViewModel load-more-replies seam + loading state

Adds an injectable fetchMoreCommentsOperation, a loadingMoreElementIds
set reconciled against the live tree, and loadMoreReplies dispatch.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011EaJJgwwrWu2oxRdkAZtFY"
```

---

### Task 5: Spud — UI wiring (cell tap + spinner + VC dispatch + toast)

**Files:**
- Modify: `Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentViewModel.swift` (add `isLoadingMore`)
- Modify: `Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentCell.swift` (tap routing, spinner, a11y)
- Modify: `Spud/Scenes/PostDetail/Content/PostDetailViewController.swift` (cell-provider closure, `handleLoadMoreTap`, `reconfigureCommentRows`, failure toast)

**Interfaces:**
- Consumes: `PostDetailViewModel.isLoadingMore/markLoadingMore/clearLoadingMore/loadMoreReplies` (Task 4), `PostDetailCommentRow.moreParentId`, `ToastPresenter.shared.show(_:in:)`, `alertService.handle(_:for:)`.
- Produces: `PostDetailCommentCell.loadMoreTapped: (() -> Void)?`; `PostDetailCommentViewModel(isLoadingMore:)`.

- [ ] **Step 1: Add `isLoadingMore` to `PostDetailCommentViewModel`.** Add a stored `let isLoadingMore: Bool` and an `isLoadingMore: Bool = false` init parameter (default false so existing construction sites — snapshot tests, etc. — are unaffected). Assign it in `init`. Update the "more" accessibility so the loading state reads correctly — where `collapseAccessibilityHint` is set for `isMore` (around line 419):
```swift
        if isMore {
            subtitleAccessibilityLabel = nil
            collapseAccessibilityHint = isLoadingMore
                ? NSLocalizedString("Loading replies", comment: "VoiceOver hint while more replies load")
                : NSLocalizedString("Loads more replies", comment: "VoiceOver hint for the load-more-replies row")
        }
```

- [ ] **Step 2: Wire the tap + spinner in `PostDetailCommentCell`.**

Add the closure (near the other closures, ~line 15-67) and reset it in `prepareForReuse`:
```swift
    /// Fired when the user taps a "load more replies" placeholder row.
    var loadMoreTapped: (() -> Void)?
```
```swift
        // in prepareForReuse(), alongside the other closure resets
        loadMoreTapped = nil
```

Add cell state + a spinner. Near the other private stored flags:
```swift
    private var isMoreRow = false
    private var isLoadingMoreRow = false

    private lazy var moreActivityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()
```
Add it to `contentView` in `init` and constrain it centered on `authorLabel`, just trailing the text (do NOT pin `contentView.trailing` to it, so `authorLabel`'s own layout is untouched):
```swift
        contentView.addSubview(moreActivityIndicator)
        NSLayoutConstraint.activate([
            moreActivityIndicator.centerYAnchor.constraint(equalTo: authorLabel.centerYAnchor),
            moreActivityIndicator.leadingAnchor.constraint(equalTo: authorLabel.trailingAnchor, constant: 8),
        ])
```

In `configure(with:)`, in the `isMore` branch (currently lines 578-585), record the flags and render the loading vs idle state:
```swift
        if viewModel.isMore {
            isMoreRow = true
            isLoadingMoreRow = viewModel.isLoadingMore
            if viewModel.isLoadingMore {
                authorLabel.attributedText = NSAttributedString(
                    string: NSLocalizedString("Loading replies…", comment: "Placeholder row while more replies load"),
                    attributes: [
                        .font: UIFont.preferredFont(forTextStyle: .body),
                        .foregroundColor: UIColor.secondaryLabel,
                    ]
                )
                moreActivityIndicator.startAnimating()
            } else {
                authorLabel.attributedText = viewModel.moreText
                moreActivityIndicator.stopAnimating()
            }
            subtitleLabel.attributedText = nil
            bodyView.setBlocks([])
            bodyView.isHidden = true
            messageLabel.attributedText = nil
            messageLabel.isHidden = true
            clearBadges()
        } else {
            isMoreRow = false
            isLoadingMoreRow = false
            moreActivityIndicator.stopAnimating()
            // ... existing non-more branch unchanged ...
```
(Also add `isMoreRow = false; isLoadingMoreRow = false; moreActivityIndicator.stopAnimating()` to `prepareForReuse`.)

Change the recognizer enablement (line 712) so the more-row IS tappable (route it in the handler instead of disabling):
```swift
        // The "load more" row IS tappable (routed to loadMoreTapped in handleCollapseTap); a
        // loading row ignores taps. A normal row collapses.
        collapseTapGestureRecognizer.isEnabled = true
```
And branch at the end of `handleCollapseTap(_:)` (replace the final `collapseTapped?()`):
```swift
        if isMoreRow {
            if !isLoadingMoreRow {
                loadMoreTapped?()
            }
            return
        }

        collapseTapped?()
```
Keep the `.button` accessibility trait for `isMore` (existing lines 723-728); optionally suppress it while loading:
```swift
        if viewModel.isMore {
            accessibilityTraits = viewModel.isLoadingMore ? .updatesFrequently : .button
        } else {
            accessibilityTraits = .none
        }
```

- [ ] **Step 3: Wire the VC.** In `PostDetailViewController.swift`:

Pass the loading flag into the per-cell VM (in the `.comment` cell-provider branch where `PostDetailCommentViewModel(...)` is built, ~line 2050):
```swift
                    isLoadingMore: self?.viewModel.isLoadingMore(elementId: elementId) ?? false,
```
Assign the new closure (next to `cell.collapseTapped = ...`, ~line 2100):
```swift
                cell.loadMoreTapped = { [weak self] in
                    self?.handleLoadMoreTap(elementId: elementId, parentServerId: row.moreParentId)
                }
```
Add the handler + helpers (place near `toggleCollapse` / the other comment-action handlers):
```swift
    /// Tapping a "load more replies" row: mark it loading, reconfigure the cell to show the
    /// spinner, then fetch + splice. On success the comment observation replaces the row; on
    /// failure revert the row and toast.
    private func handleLoadMoreTap(elementId: Int64, parentServerId: Int64?) {
        guard let parentServerId else { return }
        guard !viewModel.isLoadingMore(elementId: elementId) else { return }

        viewModel.markLoadingMore(elementId: elementId)
        reconfigureCommentRows([elementId])

        Task { [weak self] in
            guard let self else { return }
            do {
                try await viewModel.loadMoreReplies(elementId: elementId, parentServerId: parentServerId)
                // Success: observePostDetailComments emits the spliced tree; applySnapshot replaces
                // the placeholder row, and updateOrderedComments clears the loading flag.
            } catch {
                alertService.handle(error, for: .fetchComments)
                viewModel.clearLoadingMore(elementId: elementId)
                reconfigureCommentRows([elementId])
                showLoadMoreFailureToast()
            }
        }
    }

    /// Re-runs the cell provider for the given comment rows without changing the snapshot's item
    /// set (a loading-flag flip doesn't alter which items exist, so a plain apply won't reconfigure
    /// them).
    private func reconfigureCommentRows(_ elementIds: [Int64]) {
        var snapshot = dataSource.snapshot()
        let items = elementIds
            .map { Item.comment(elementId: $0) }
            .filter { snapshot.indexOfItem($0) != nil }
        guard !items.isEmpty else { return }
        snapshot.reconfigureItems(items)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func showLoadMoreFailureToast() {
        guard let window = view.window else { return }
        ToastPresenter.shared.show(
            NSLocalizedString("Couldn't load more replies", comment: "Toast when loading more comment replies fails"),
            in: window
        )
    }
```

- [ ] **Step 4: Build the app + test targets**

```bash
make build
make test-only ONLY=SpudTests
```
Expected: build succeeds (0 new warnings beyond the known benign rpath one); `SpudTests` still green (the cell/VC changes don't break existing tests).

- [ ] **Step 5: Verify on-device (tap-gated).** idb tap automation is dead here, so verify with a booted sim + the real app OR an XCUITest. Minimum bar: run the app against an instance/post with a truncated chain (or a signed-out browse of a large thread), confirm the "N more replies" row now shows a spinner on tap and expands into the loaded replies, and that a forced failure reverts + toasts. If writing an XCUITest, stub the neutral `parent_id` request (SBT), tap `staticTexts`/the more-row, assert a new comment cell appears — model it on the existing `SpudUITests` post-detail flow, and remember every referenced stub fixture file must exist in the UITest target. (This on-device/UITest check is the runtime gate for the whole feature; note explicitly in the commit whether it was an XCUITest or a manual sim check.)

- [ ] **Step 6: SwiftFormat + commit**

```bash
mint run swiftformat Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentViewModel.swift Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentCell.swift Spud/Scenes/PostDetail/Content/PostDetailViewController.swift
git add Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentViewModel.swift Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentCell.swift Spud/Scenes/PostDetail/Content/PostDetailViewController.swift
# plus any XCUITest file
git commit -m "feat: wire load-more-replies tap, spinner, and error toast

The 'N more replies' row is now tappable: shows an inline spinner while
fetching, expands into the loaded subtree on success (via the comment
observation), and reverts + toasts on failure. VoiceOver reflects the
loading state.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011EaJJgwwrWu2oxRdkAZtFY"
```

> **Note (no snapshot for the loading state):** a live `UIActivityIndicatorView` is non-deterministic, so the loading row is intentionally not snapshot-tested. The idle "N more replies" row keeps whatever existing snapshot coverage it has; if `make snapshot` (Task 7) flags a drift on a comment-tree screen, re-record that one class only.

---

### Task 6: Documentation

**Files:**
- Modify/Create: the post-detail comment-reading capability doc under `docs/features/` (find it: `grep -rl "comment" docs/features/*.md` — the comment-loading/post-detail doc; if none dedicated exists, add a `comment-tree-loading.md` following `docs/features/README.md`'s `_TEMPLATE.md`)
- Modify: `docs/features/README.md` (the capability table AND the "Feature coverage by area" map — both)

- [ ] **Step 1: Update the capability doc.** Add behavior + rules for load-more-replies and **Scenarios** in Given/When/Then form, e.g.:
  - Given a comment reports more replies than were loaded, When the tree renders, Then a "N more replies" row appears beneath it.
  - Given a "N more replies" row, When the user taps it, Then a spinner shows and the missing subtree loads inline in place.
  - Given a very deep subtree beyond the fetch cap, When it expands, Then a fresh "N more replies" row appears deeper (self-healing).
  - Given the fetch fails, When the user tapped, Then the row reverts and a "Couldn't load more replies" toast appears; tapping again retries.
  Keep `Status:` honest and `Surfaces:` = the union of scenario tags. No `.swift` links.

- [ ] **Step 2: Update `docs/features/README.md`** — add/adjust the row in the capability table and the entry in the by-area map (both sections; they drift independently).

- [ ] **Step 3: Commit**

```bash
git add docs/features/
git commit -m "docs: document load-more-replies (inline subtree expansion)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011EaJJgwwrWu2oxRdkAZtFY"
```

---

### Task 7: Finalize — restore the LemmyKit pin, full verify, merge

**Files:**
- Modify: `project.yml` (restore + bump the LemmyKit `revision:` pin — this time COMMITTED)

- [ ] **Step 1: Full local verify with the override still in place.** Format everything, then run the whole plan + snapshots:
```bash
mint run swiftformat .
make test
make snapshot
```
Expected: `make test` green (all five unit-test targets + SpudUITests); `make snapshot` green on the reference sim (re-record one class only if a comment-tree screen legitimately changed). If a background `make test`/`make snapshot` was launched, poll `pgrep -f "xcodebuild.*-scheme Spud"` and wait for exit before trusting the result — don't infer green from the process merely ending.

- [ ] **Step 2: Push LemmyKit (USER-GATED).** The committed pin must reference a pushed revision. **Ask the user to approve pushing the LemmyKit commit** (per the commit/push preference). On approval:
```bash
cd /Users/denis/dev/info.ddenis/Spud/LemmyKit
git log --oneline -1           # confirm HEAD is the Task 1 commit
git push origin HEAD:main      # or the branch the pin tracks — confirm with the user
git rev-parse HEAD             # capture the SHA for the pin
```

- [ ] **Step 3: Restore + bump the committed pin.** In the Spud worktree, edit `project.yml`: replace the dev `path:` override with the pushed revision (keep it a `revision:`, NOT a release tag — this is unvalidated against a real 1.0 server):
```yaml
  LemmyKit:
    url: https://github.com/shadone/LemmyKit
    revision: <SHA from Step 2>
```
Then resolve against the remote and rebuild:
```bash
make project
rm -f Spud.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
rm -rf ~/Library/Caches/org.swift.swiftpm/repositories
xcodebuild -resolvePackageDependencies -project Spud.xcodeproj -skipPackagePluginValidation -skipMacroValidation
make build
make test-only ONLY=SpudDataKitTests
```
Expected: resolves the pinned remote revision (no local path); build + tests green.

- [ ] **Step 4: Commit the pin bump**
```bash
git add project.yml
git commit -m "chore: bump LemmyKit pin for getCommentsNeutral(parentId:)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011EaJJgwwrWu2oxRdkAZtFY"
```

- [ ] **Step 5: Integrate the branch.** Use the `superpowers:finishing-a-development-branch` skill. Before merging into local `main`: re-check `main..feat/load-more-replies` and file overlap right before the merge (shared checkout, parallel agents — local `main` may have advanced). Follow this repo's worktree-merge ceremony (see the workspace `CLAUDE.md`: `git annex restage` first if merging in the shared checkout; or the throwaway-worktree merge trick if `main` isn't checked out anywhere), then clean up the worktree (`rm -rf` + `git worktree prune` + `git branch -d`).

---

## Self-Review

**Spec coverage** (against `2026-07-14-load-more-replies-design.md`):
- §3 LemmyKit neutral parentId fetch → Task 1. ✓
- §4 `fetchMoreComments` bounded pagination → Task 3. ✓ (v3 single-page / v4 cursor handled by the `nextPage` loop.)
- §5 `spliceMoreComments` localized splice (locate placeholder, upsert, thread-minus-parent, position shift, delete placeholder, regenerate frontier, idempotent) → Task 2. ✓
- §6 UI (dedicated-recognizer-vs-reuse resolved to reuse; loading `Set<elementId>`; a11y) → Task 5 + Task 4. ✓
- §7 error handling (toast + log; row is retry) → Task 5 (`ToastPresenter` + `alertService.handle`). ✓ (Corrected from the spec's "AlertService toast" — AlertService is log-only; ToastPresenter shows toasts.)
- §8 testing (LemmyKit v3/v4, importer splice incl. idempotency + frontier, VM, on-device/UITest) → Tasks 1,2,3,4,5. ✓ Snapshot intentionally omitted for the non-deterministic spinner (noted).
- §9 docs + local-path-override rollout, pin bump last → Tasks 6, 7. ✓
- §10 out-of-scope (no migration, no detector change, no focused screen) → honored. ✓

**Placeholder scan:** The only free-form step is Task 3 Step 2's fixture assembly (an inline v3 comments JSON or a copied fixture) — flagged explicitly with the completeness gotcha and a "passing test is the deliverable, not a stub" instruction. No `TODO`/`TBD` left as deliverables.

**Type consistency:** `getCommentsNeutral(parentId: Int64, sort: CommentSort, pageCursor: Cursor?)` (Task 1) ⇄ called with `parentId: parentServerId` in `fetchMoreComments` (Task 3). `fetchMoreComments(serverPostId: Lemmy.PostID, parentServerId: Int64, sortType:)` ⇄ `fetchMoreCommentsOperation: (Int64, Lemmy.CommentSortType)` (Task 4) ⇄ `loadMoreReplies(elementId:parentServerId:)` reads `row.moreParentId` (Int64, Task 5). `spliceMoreComments(...parentServerId: Int64...)` (Task 2) ⇄ called from `fetchMoreComments` (Task 3). Cell `loadMoreTapped: (() -> Void)?` (Task 5) ⇄ assigned in the VC cell provider (Task 5). `isLoadingMore(elementId:)`/`markLoadingMore`/`clearLoadingMore` names consistent across Tasks 4 and 5. Consistent.
