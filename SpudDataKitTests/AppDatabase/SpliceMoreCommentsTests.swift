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
}
