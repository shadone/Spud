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
    private func seed(
        _ appDatabase: AppDatabase,
        serverPostId: Int64
    ) async throws -> (accountId: Int64, siteId: Int64, postRowId: Int64, person: Person, community: Community, post: Post) {
        try await CommentSeed.seed(appDatabase, serverPostId: serverPostId, accountKeychainId: "keychain-1")
    }

    private func elements(_ appDatabase: AppDatabase, postRowId: Int64) async throws -> [CommentElementRecord] {
        try await CommentSeed.elements(appDatabase, postRowId: postRowId)
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
        #expect(before[0].commentId != nil) // the parent comment row
        #expect(before[1].commentId == nil) // the "load more" placeholder
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
        #expect(after.count == 2) // parent + child, placeholder gone
        #expect(after.allSatisfy { $0.commentId != nil }) // no placeholder rows
        #expect(after[0].depth == 1) // top-level comment (root "0" counts)
        #expect(after[1].depth == 2) // its child
        #expect(after.map(\.position) == [0, 1]) // dense, ordered
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
        #expect(after.count == 3) // parent, child, new placeholder
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
        #expect(after.count == 1) // unchanged
    }

    @Test
    func spliceInsertsSubtreeForNestedParent() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let seeded = try await seed(appDatabase, serverPostId: 1)

        // Top-level A (id 1) with child B (id 2) that claims 1 missing grandchild.
        let a = CommentView.fake(
            comment: .fake(id: 1, post: seeded.post, creator: seeded.person, parent: .root),
            creator: seeded.person, post: seeded.post, community: seeded.community, childCount: 1
        )
        let b = CommentView.fake(
            comment: .fake(id: 2, post: seeded.post, creator: seeded.person, parent: CommentPath(path: "0.1")),
            creator: seeded.person, post: seeded.post, community: seeded.community, childCount: 1
        )
        try await appDatabase.upsertComments(
            forServerPostId: 1, accountId: seeded.accountId, siteId: seeded.siteId,
            sortType: .Hot, comments: [a, b]
        )
        let before = try await elements(appDatabase, postRowId: seeded.postRowId)
        #expect(before.count == 3) // A, B, placeholder(under B)
        #expect(before[2].commentId == nil)
        #expect(before[2].moreParentId == 2)

        // Load B's replies: B (childCount 0) + grandchild C (id 3, path 0.1.2.3).
        let bLoaded = CommentView.fake(
            comment: .fake(id: 2, post: seeded.post, creator: seeded.person, parent: CommentPath(path: "0.1")),
            creator: seeded.person, post: seeded.post, community: seeded.community, childCount: 0
        )
        let c = CommentView.fake(
            comment: .fake(id: 3, post: seeded.post, creator: seeded.person, parent: CommentPath(path: "0.1.2")),
            creator: seeded.person, post: seeded.post, community: seeded.community, childCount: 0
        )
        try await appDatabase.spliceMoreComments(
            forServerPostId: 1, accountId: seeded.accountId, siteId: seeded.siteId,
            sortType: .Hot, parentServerId: 2, comments: [bLoaded, c]
        )

        let after = try await elements(appDatabase, postRowId: seeded.postRowId)
        #expect(after.count == 3) // A, B, C — placeholder replaced by C
        #expect(after.allSatisfy { $0.commentId != nil })
        #expect(after.map(\.depth) == [1, 2, 3])
        #expect(after.map(\.position) == [0, 1, 2])
    }

    @Test
    func spliceShiftsDownstreamSiblingPositions() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let seeded = try await seed(appDatabase, serverPostId: 1)

        // Tree: A (id 10, claims 1 missing child) then X (id 30) with child Y (id 31). The third
        // comment makes A a detected branch-end so it gets a placeholder (findCommentsWithMissingChildren
        // only flags the last comment of each path-branch).
        let a = CommentView.fake(
            comment: .fake(id: 10, post: seeded.post, creator: seeded.person, parent: .root),
            creator: seeded.person, post: seeded.post, community: seeded.community, childCount: 1
        )
        let x = CommentView.fake(
            comment: .fake(id: 30, post: seeded.post, creator: seeded.person, parent: .root),
            creator: seeded.person, post: seeded.post, community: seeded.community, childCount: 0
        )
        let y = CommentView.fake(
            comment: .fake(id: 31, post: seeded.post, creator: seeded.person, parent: CommentPath(path: "0.30")),
            creator: seeded.person, post: seeded.post, community: seeded.community, childCount: 0
        )
        try await appDatabase.upsertComments(
            forServerPostId: 1, accountId: seeded.accountId, siteId: seeded.siteId,
            sortType: .Hot, comments: [a, x, y]
        )
        let before = try await elements(appDatabase, postRowId: seeded.postRowId)
        #expect(before.count == 4) // A, placeholder(under 10), X, Y
        #expect(before.map(\.depth) == [1, 2, 1, 2])
        #expect(before[1].moreParentId == 10)

        // Splice 2 descendants under A -> the rows after the placeholder (X, Y) shift by (2 - 1) = 1.
        let aLoaded = CommentView.fake(
            comment: .fake(id: 10, post: seeded.post, creator: seeded.person, parent: .root),
            creator: seeded.person, post: seeded.post, community: seeded.community, childCount: 0
        )
        let b = CommentView.fake(
            comment: .fake(id: 11, post: seeded.post, creator: seeded.person, parent: CommentPath(path: "0.10")),
            creator: seeded.person, post: seeded.post, community: seeded.community, childCount: 0
        )
        let cc = CommentView.fake(
            comment: .fake(id: 12, post: seeded.post, creator: seeded.person, parent: CommentPath(path: "0.10")),
            creator: seeded.person, post: seeded.post, community: seeded.community, childCount: 0
        )
        try await appDatabase.spliceMoreComments(
            forServerPostId: 1, accountId: seeded.accountId, siteId: seeded.siteId,
            sortType: .Hot, parentServerId: 10, comments: [aLoaded, b, cc]
        )

        let after = try await elements(appDatabase, postRowId: seeded.postRowId)
        #expect(after.count == 5) // A, B, C, X, Y
        #expect(after.allSatisfy { $0.commentId != nil })
        #expect(after.map(\.position) == [0, 1, 2, 3, 4])
        #expect(after.map(\.depth) == [1, 2, 2, 1, 2]) // X (d1) and Y (d2) shifted to the end
    }
}
