//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import LemmyKit
@testable import SpudDataKit

/// Seeds instance/site/account/post and returns the ids needed to import
/// comments. Shared by every test suite exercising the comment importer
/// (`upsertComments` / `spliceMoreComments`) so each one doesn't hand-roll its
/// own fixture rows.
@MainActor
enum CommentSeed {
    static func seed(
        _ appDatabase: AppDatabase,
        serverPostId: Int64,
        accountKeychainId: String
    ) async throws -> (
        accountId: Int64,
        siteId: Int64,
        postRowId: Int64,
        person: Lemmy.Person,
        community: Lemmy.Community,
        post: Lemmy.Post
    ) {
        let (accountId, siteId) = try await appDatabase.writer.write { db -> (Int64, Int64) in
            var instance = InstanceRecord(actorId: "https://example.com")
            try instance.insert(db)
            var site = SiteRecord(instanceId: instance.id!)
            try site.insert(db)
            var account = AccountRecord(
                siteId: site.id!,
                accountKeychainId: accountKeychainId,
                isSignedOutAccountType: false
            )
            try account.insert(db)
            return (account.id!, site.id!)
        }
        let person = Lemmy.Person.fake
        let community = Lemmy.Community.fake
        let post = Lemmy.Post.fake(creator: person, community: community, id: Lemmy.PostID(serverPostId))
        let postRowId = try await appDatabase.upsertPost(
            from: .fake(post: post, creator: person, community: community),
            accountId: accountId,
            siteId: siteId
        )
        return (accountId, siteId, postRowId, person, community, post)
    }

    /// Fetches the stored `CommentElementRecord` rows for a post, in display
    /// (`position ASC`) order, scoped to `Hot` sort.
    static func elements(_ appDatabase: AppDatabase, postRowId: Int64) async throws -> [CommentElementRecord] {
        try await appDatabase.writer.read { db in
            try CommentElementRecord
                .filter(Column("postId") == postRowId)
                .filter(Column("sortType") == Lemmy.CommentSortType.Hot.rawValue)
                .order(Column("position"))
                .fetchAll(db)
        }
    }
}
