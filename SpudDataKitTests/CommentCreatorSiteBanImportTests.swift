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

/// Verifies `CommentImporter` mirrors the `CommentView`'s instance-wide creator
/// ban (`creatorBanned`) onto the creator's `person` row — symmetric with
/// `PostImporter`. The neutral bare `Person` no longer carries the site-ban, so
/// without this mirror a comment authored by a site-banned user would leave
/// `person.isBanned == false` and the comment author-status SUSPENDED indicator
/// (which reads `isCreatorSiteBanned` from the joined `person.isBanned`) would
/// never light.
struct CommentCreatorSiteBanImportTests {
    private func seedAccount(_ appDatabase: AppDatabase) async throws -> (accountId: Int64, siteId: Int64) {
        try await appDatabase.writer.write { db in
            var instance = InstanceRecord(actorId: "https://example.com")
            try instance.insert(db)
            var site = SiteRecord(instanceId: instance.id!)
            try site.insert(db)
            var account = AccountRecord(
                siteId: site.id!,
                accountKeychainId: "keychain-comment-creator-site-ban",
                isSignedOutAccountType: false
            )
            try account.insert(db)
            return (account.id!, site.id!)
        }
    }

    /// A comment authored by a site-banned user lands `person.isBanned == true`,
    /// while the post's own (non-banned) author stays unbanned — proving the
    /// mirror is keyed on the comment view's creator, not bled in from the post.
    @Test
    func upsertComment_mirrorsCreatorSiteBanOntoPerson() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId) = try await seedAccount(appDatabase)

        let community = Lemmy.Community.fake
        let postAuthor = Lemmy.Person.fake(id: 1, name: "postauthor")
        let post = Lemmy.Post.fake(creator: postAuthor, community: community)
        _ = try await appDatabase.upsertPost(
            from: .fake(post: post, creator: postAuthor, community: community),
            accountId: accountId,
            siteId: siteId
        )

        // A distinct commenter who is banned instance-wide.
        let bannedCommenter = Lemmy.Person.fake(id: 2, name: "banned-commenter")
        let commentView = Lemmy.CommentView.fake(
            comment: .fake(id: 10, post: post, creator: bannedCommenter, parent: .root),
            creator: bannedCommenter,
            post: post,
            community: community,
            childCount: 0,
            creatorBanned: true
        )
        try await appDatabase.upsertComment(from: commentView, accountId: accountId, siteId: siteId)

        let (commenterBanned, postAuthorBanned) = try await appDatabase.writer.read { db in
            let commenter = try PersonRecord
                .filter(Column("personId") == Int64(bannedCommenter.id))
                .fetchOne(db)
            let author = try PersonRecord
                .filter(Column("personId") == Int64(postAuthor.id))
                .fetchOne(db)
            return (commenter?.isBanned, author?.isBanned)
        }
        #expect(commenterBanned == true, "the comment creator's site-ban should mirror onto person.isBanned")
        #expect(postAuthorBanned == false, "a non-banned post author should stay unbanned")
    }
}
