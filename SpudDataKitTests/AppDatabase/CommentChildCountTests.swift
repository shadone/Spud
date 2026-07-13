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

/// Coverage for `v36_commentChildCount`: `CommentImporter` populating
/// `CommentRecord.childCount` from the fetched `CommentView`, and the
/// `commentChildCountSync` one-shot read that a Phase-3 comment-subtree
/// reminder will baseline/poll against (mirrors `postNumberOfCommentsSync`
/// for the whole-post case; see `ReminderQueries.swift`).
struct CommentChildCountTests {
    private func seedAccount(_ appDatabase: AppDatabase, keychainId: String) async throws -> (accountId: Int64, siteId: Int64) {
        try await appDatabase.writer.write { db in
            var instance = InstanceRecord(actorId: "https://example.com")
            try instance.insert(db)
            var site = SiteRecord(instanceId: instance.id!)
            try site.insert(db)
            var account = AccountRecord(
                siteId: site.id!,
                accountKeychainId: keychainId,
                isSignedOutAccountType: false
            )
            try account.insert(db)
            return (account.id!, site.id!)
        }
    }

    /// Importing a `CommentView` whose server `child_count` is a known value
    /// persists it onto the comment row, and `commentChildCountSync` reads it
    /// back — the same accessor (`view.comment.childCount`) Phase-1 already
    /// used to size the "load more" placeholder's `moreChildCount`.
    @Test
    func importedCommentChildCount_readableViaSync() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let keychainId = "keychain-comment-child-count"
        let (accountId, siteId) = try await seedAccount(appDatabase, keychainId: keychainId)

        let community = Lemmy.Community.fake
        let postAuthor = Lemmy.Person.fake(id: 1, name: "postauthor")
        let post = Lemmy.Post.fake(creator: postAuthor, community: community)
        _ = try await appDatabase.upsertPost(
            from: .fake(post: post, creator: postAuthor, community: community),
            accountId: accountId,
            siteId: siteId
        )

        let commenter = Lemmy.Person.fake(id: 2, name: "commenter")
        let commentView = Lemmy.CommentView.fake(
            comment: .fake(id: 10, post: post, creator: commenter, parent: .root),
            creator: commenter,
            post: post,
            community: community,
            childCount: 7
        )
        try await appDatabase.upsertComment(from: commentView, accountId: accountId, siteId: siteId)

        let childCount = appDatabase.commentChildCountSync(forKeychainId: keychainId, serverCommentId: 10)
        #expect(childCount == 7)
    }

    /// A comment row written before this column existed (or otherwise never
    /// re-imported) stores `NULL` — `commentChildCountSync` must read that back
    /// as `nil`, not throw or crash decoding a non-optional `Int64` out of a
    /// NULL column.
    @Test
    func commentWithNoChildCount_syncReadsNil() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let keychainId = "keychain-comment-child-count-nil"
        let (accountId, siteId) = try await seedAccount(appDatabase, keychainId: keychainId)

        let community = Lemmy.Community.fake
        let postAuthor = Lemmy.Person.fake(id: 1, name: "postauthor")
        let post = Lemmy.Post.fake(creator: postAuthor, community: community)
        _ = try await appDatabase.upsertPost(
            from: .fake(post: post, creator: postAuthor, community: community),
            accountId: accountId,
            siteId: siteId
        )

        try await appDatabase.writer.write { db in
            guard let postRowId = try PostRecord
                .filter(Column("accountId") == accountId)
                .filter(Column("postId") == Int64(post.id))
                .fetchOne(db)?
                .id
            else {
                Issue.record("expected the seeded post to be present")
                return
            }
            guard let creatorRowId = try PersonRecord
                .filter(Column("siteId") == siteId)
                .filter(Column("personId") == Int64(postAuthor.id))
                .fetchOne(db)?
                .id
            else {
                Issue.record("expected the seeded post creator to be present")
                return
            }

            // Constructed directly (not via CommentImporter) with the default
            // `childCount: nil` — standing in for a row written before
            // `v36_commentChildCount` populated this column.
            var comment = CommentRecord(
                postId: postRowId,
                creatorId: creatorRowId,
                localCommentId: 20,
                body: "no child count yet",
                published: Date()
            )
            try comment.insert(db)
        }

        let childCount = appDatabase.commentChildCountSync(forKeychainId: keychainId, serverCommentId: 20)
        #expect(childCount == nil)
    }
}
