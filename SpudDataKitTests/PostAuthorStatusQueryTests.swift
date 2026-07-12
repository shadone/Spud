//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import Testing
@testable import SpudDataKit

/// Verifies the two post read queries surface the author's status: the per-post
/// creator context (moderator / admin / banned-from-community) from the post row
/// and the site-ban / bot / deleted flags from the joined creator `person` row —
/// in both `PostListRow` (feed) and `PostDetailHeaderRow` (detail).
struct PostAuthorStatusQueryTests {
    private func seedAccount(_ appDatabase: AppDatabase) async throws -> (accountId: Int64, siteId: Int64) {
        try await appDatabase.writer.write { db in
            var instance = InstanceRecord(actorId: "https://example.com")
            try instance.insert(db)
            var site = SiteRecord(instanceId: instance.id!)
            try site.insert(db)
            var account = AccountRecord(
                siteId: site.id!,
                accountKeychainId: "keychain-author-status-query",
                isSignedOutAccountType: false
            )
            try account.insert(db)
            return (account.id!, site.id!)
        }
    }

    /// A creator that is site-banned, a bot, and deleted, whose post carries all
    /// three per-community context flags. In the neutral (v4) shape the bare
    /// `Person` carries `botAccount`/`deleted` while the instance-wide ban rides on
    /// the `PostView` as `creatorBanned` (the importer mirrors it onto the creator's
    /// person row, which the query reads back as `isCreatorSiteBanned`).
    private func makeView() -> Lemmy.PostView {
        let creator = Lemmy.Person.fake(botAccount: true, deleted: true)
        let community = Lemmy.Community.fake
        let post = Lemmy.Post.fake(creator: creator, community: community)
        return Lemmy.PostView.fake(
            post: post,
            creator: creator,
            community: community,
            creatorBannedFromCommunity: true,
            creatorIsModerator: true,
            creatorIsAdmin: true,
            creatorBanned: true
        )
    }

    @Test
    func postDetailHeader_surfacesAuthorStatus() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId) = try await seedAccount(appDatabase)

        let rowId = try await appDatabase.writer.write { db in
            try AppDatabase.upsertPost(from: makeView(), accountId: accountId, siteId: siteId, in: db)
        }

        var iterator = appDatabase.observePostDetailHeader(postRowId: rowId).makeAsyncIterator()
        let header = try #require(await iterator.next() ?? nil)

        #expect(header.isCreatorModerator == true)
        #expect(header.isCreatorAdmin == true)
        #expect(header.isCreatorBannedFromCommunity == true)
        #expect(header.isCreatorSiteBanned == true)
        #expect(header.isCreatorBot == true)
        #expect(header.isCreatorAccountDeleted == true)
    }

    @Test
    func postListRow_surfacesAuthorStatus() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId) = try await seedAccount(appDatabase)

        let postRowId = try await appDatabase.writer.write { db in
            try AppDatabase.upsertPost(from: makeView(), accountId: accountId, siteId: siteId, in: db)
        }

        // Wire the imported post into a feed so `observePostListRows` returns it.
        let feedId = try await appDatabase.writer.write { db -> Int64 in
            var feed = FeedRecord(
                accountId: accountId,
                feedKey: UUID().uuidString,
                savedOnly: false,
                sortType: "Hot",
                createdAt: Date()
            )
            try feed.insert(db)
            var page = PageRecord(feedId: feed.id!, position: 0, createdAt: Date())
            try page.insert(db)
            var element = PageElementRecord(pageId: page.id!, postId: postRowId, position: 0)
            try element.insert(db)
            return feed.id!
        }

        var rows: [PostListRow] = []
        for await emission in appDatabase.observePostListRows(feedId: feedId) {
            rows = emission
            break
        }

        let row = try #require(rows.first)
        #expect(row.isCreatorModerator == true)
        #expect(row.isCreatorAdmin == true)
        #expect(row.isCreatorBannedFromCommunity == true)
        #expect(row.isCreatorSiteBanned == true)
        #expect(row.isCreatorBot == true)
        #expect(row.isCreatorAccountDeleted == true)
    }
}
