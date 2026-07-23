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
    private func seed(
        _ appDatabase: AppDatabase,
        serverPostId: Int64
    ) async throws -> (accountId: Int64, siteId: Int64, postRowId: Int64, person: Person, community: Community, post: Post) {
        try await CommentSeed.seed(appDatabase, serverPostId: serverPostId, accountKeychainId: "keychain-stable-identity")
    }

    private func elements(_ appDatabase: AppDatabase, postRowId: Int64) async throws -> [CommentElementRecord] {
        try await CommentSeed.elements(appDatabase, postRowId: postRowId)
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
        // CommentPath.depth counts the synthetic root ("0") element, so a
        // top-level comment is depth 1, not 0 -- matching the convention
        // already asserted in SpliceMoreCommentsTests.
        #expect(rows.map(\.depth) == [1, 2, 1])
    }

    /// A non-pruning (additive) import must not delete comments absent from
    /// its own given set, and the walk's later authoritative re-import must
    /// still find the same rows -- keeping their element ids. This is the
    /// shape of `LemmyService.fetchComments`'s walk: `a`, `b`, `c` stand in
    /// for pages 1, 2, 3 of a listing; re-walking sends page 1 (`a`) first,
    /// additively, before pages 2 and 3 (`b`, `c`) have been re-fetched -- and
    /// must not prune them away in the meantime.
    @Test
    func nonPruningImportPreservesLaterCommentsUntilFinalReconcile() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let seeded = try await seed(appDatabase, serverPostId: 1)

        let a = CommentView.fake(
            comment: .fake(id: 10, post: seeded.post, creator: seeded.person, parent: .root),
            creator: seeded.person, post: seeded.post, community: seeded.community, childCount: 0
        )
        let b = CommentView.fake(
            comment: .fake(id: 11, post: seeded.post, creator: seeded.person, parent: .root),
            creator: seeded.person, post: seeded.post, community: seeded.community, childCount: 0
        )
        let c = CommentView.fake(
            comment: .fake(id: 12, post: seeded.post, creator: seeded.person, parent: .root),
            creator: seeded.person, post: seeded.post, community: seeded.community, childCount: 0
        )

        try await appDatabase.upsertComments(
            forServerPostId: 1, accountId: seeded.accountId, siteId: seeded.siteId,
            sortType: .Hot, comments: [a, b, c]
        )
        let originalIds = try await elements(appDatabase, postRowId: seeded.postRowId).compactMap(\.id)
        #expect(originalIds.count == 3)

        // Re-import only `a` (page 1) with pruning OFF -- must not delete `b`
        // and `c` (pages 2 and 3), which this call knows nothing about.
        try await appDatabase.upsertComments(
            forServerPostId: 1, accountId: seeded.accountId, siteId: seeded.siteId,
            sortType: .Hot, comments: [a], pruningAbsentElements: false
        )
        let afterAdditiveImport = try await elements(appDatabase, postRowId: seeded.postRowId)
        #expect(
            afterAdditiveImport.count == 3,
            "a non-pruning import must not delete comments absent from its own comment set"
        )

        // The walk completes: the full set is re-imported with pruning back on.
        try await appDatabase.upsertComments(
            forServerPostId: 1, accountId: seeded.accountId, siteId: seeded.siteId,
            sortType: .Hot, comments: [a, b, c]
        )
        let finalIds = try await elements(appDatabase, postRowId: seeded.postRowId).compactMap(\.id)

        #expect(finalIds.count == 3)
        #expect(finalIds[1] == originalIds[1], "comment b (page 2) must keep its element id across the re-walk")
        #expect(finalIds[2] == originalIds[2], "comment c (page 3) must keep its element id across the re-walk")
    }
}
