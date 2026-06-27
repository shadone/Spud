//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import Testing
@testable import SpudDataKit

/// Verifies that `PostListRow.isNsfw` is `true` when the post itself is NSFW,
/// when the community is NSFW, and `false` when both are SFW.
struct PostListRowNsfwTests {
    private var appDatabase: AppDatabase

    init() throws {
        appDatabase = try AppDatabase.inMemory()
    }

    // MARK: - Seed helpers

    @discardableResult
    private func seedAccount(keychainId: String = "kc-nsfw-1") async throws -> Int64 {
        let now = Date()
        return try await appDatabase.writer.write { db in
            try db.execute(
                sql: "INSERT INTO instance (actorId, createdAt) VALUES (?, ?)",
                arguments: ["https://\(keychainId).test", now]
            )
            let instanceId = db.lastInsertedRowID
            try db.execute(
                sql: "INSERT INTO site (instanceId, createdAt, updatedAt) VALUES (?, ?, ?)",
                arguments: [instanceId, now, now]
            )
            let siteId = db.lastInsertedRowID
            try db.execute(
                sql: """
                    INSERT INTO account
                        (siteId, accountKeychainId, isDefault, isServiceAccount, isSignedOutAccountType, createdAt, updatedAt)
                    VALUES (?, ?, 0, 0, 0, ?, ?)
                    """,
                arguments: [siteId, keychainId, now, now]
            )
            return db.lastInsertedRowID
        }
    }

    private func fetchSiteId() async throws -> Int64 {
        try await appDatabase.writer.read { db in
            try Int64.fetchOne(db, sql: "SELECT id FROM site LIMIT 1") ?? 0
        }
    }

    /// Inserts a person row and returns its row id.
    private func seedPerson(siteId: Int64, personId: Int64) async throws -> Int64 {
        let now = Date()
        return try await appDatabase.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO person
                        (siteId, personId, isAdmin, isBanned, isBotAccount, isDeleted, isLocal,
                         numberOfPosts, numberOfComments, createdAt, updatedAt)
                    VALUES (?, ?, 0, 0, 0, 0, 1, 0, 0, ?, ?)
                    """,
                arguments: [siteId, personId, now, now]
            )
            return db.lastInsertedRowID
        }
    }

    /// Inserts a community row and returns its row id.
    private func seedCommunity(accountId: Int64, communityId: Int64, isNsfw: Bool) async throws -> Int64 {
        let now = Date()
        return try await appDatabase.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO community
                        (accountId, communityId, isHidden, isLocal, isNsfw, isPostingRestrictedToMods,
                         isRemoved, subscribedState, numberOfSubscribers, numberOfPosts,
                         numberOfComments, createdAt, updatedAt)
                    VALUES (?, ?, 0, 1, ?, 0, 0, 'NotSubscribed', 0, 0, 0, ?, ?)
                    """,
                arguments: [accountId, communityId, isNsfw ? 1 : 0, now, now]
            )
            return db.lastInsertedRowID
        }
    }

    /// Inserts a post row with the given NSFW flag and title, returns its row id.
    private func seedPost(
        accountId: Int64,
        communityId: Int64,
        personId: Int64,
        postId: Int64,
        title: String,
        isNsfw: Bool
    ) async throws -> Int64 {
        let now = Date()
        return try await appDatabase.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO post
                        (accountId, communityId, creatorId, postId, title, originalPostUrl,
                         score, numberOfUpvotes, numberOfDownvotes, numberOfComments,
                         isNsfw, isRead, isSaved, isHidden, isRemoved, isLocked,
                         isFeaturedCommunity, isFeaturedLocal, isDeleted,
                         published, createdAt, updatedAt)
                    VALUES (?, ?, ?, ?, ?, ?, 0, 0, 0, 0, ?, 0, 0, 0, 0, 0, 0, 0, 0, ?, ?, ?)
                    """,
                arguments: [
                    accountId,
                    communityId,
                    personId,
                    postId,
                    title,
                    "https://example.com/post/\(postId)",
                    isNsfw ? 1 : 0,
                    now,
                    now,
                    now,
                ]
            )
            return db.lastInsertedRowID
        }
    }

    private func seedFeed(accountId: Int64) async throws -> Int64 {
        try await appDatabase.writer.write { db in
            var record = FeedRecord(
                accountId: accountId,
                feedKey: UUID().uuidString,
                savedOnly: false,
                sortType: "Hot",
                createdAt: Date()
            )
            try record.insert(db)
            return record.id!
        }
    }

    private func seedPage(feedId: Int64) async throws -> Int64 {
        try await appDatabase.writer.write { db in
            var record = PageRecord(feedId: feedId, position: 0, createdAt: Date())
            try record.insert(db)
            return record.id!
        }
    }

    private func seedPageElement(pageId: Int64, postId: Int64, position: Int64) async throws {
        try await appDatabase.writer.write { db in
            var record = PageElementRecord(pageId: pageId, postId: postId, position: position)
            try record.insert(db)
        }
    }

    // MARK: - Tests

    @Test
    func postListRow_isNsfw_trueWhenPostOrCommunityNsfw() async throws {
        let accountId = try await seedAccount()
        let siteId = try await fetchSiteId()
        let personId = try await seedPerson(siteId: siteId, personId: 1)

        // SFW community
        let sfwCommunityId = try await seedCommunity(accountId: accountId, communityId: 101, isNsfw: false)
        // NSFW community
        let nsfwCommunityId = try await seedCommunity(accountId: accountId, communityId: 102, isNsfw: true)

        // (a) post.isNsfw = true in an SFW community
        let postAId = try await seedPost(
            accountId: accountId, communityId: sfwCommunityId, personId: personId,
            postId: 1001, title: "nsfw-post", isNsfw: true
        )
        // (b) post.isNsfw = false in an NSFW community
        let postBId = try await seedPost(
            accountId: accountId, communityId: nsfwCommunityId, personId: personId,
            postId: 1002, title: "nsfw-community", isNsfw: false
        )
        // (c) both false
        let postCId = try await seedPost(
            accountId: accountId, communityId: sfwCommunityId, personId: personId,
            postId: 1003, title: "clean", isNsfw: false
        )

        let feedId = try await seedFeed(accountId: accountId)
        let pageId = try await seedPage(feedId: feedId)
        try await seedPageElement(pageId: pageId, postId: postAId, position: 0)
        try await seedPageElement(pageId: pageId, postId: postBId, position: 1)
        try await seedPageElement(pageId: pageId, postId: postCId, position: 2)

        // Consume first emission from the async observation.
        var rows: [PostListRow] = []
        for await emission in appDatabase.observePostListRows(feedId: feedId) {
            rows = emission
            break
        }

        #expect(rows.count == 3)
        #expect(rows.first { $0.title == "nsfw-post" }?.isNsfw == true, "post.isNsfw=true should propagate")
        #expect(rows.first { $0.title == "nsfw-community" }?.isNsfw == true, "community.isNsfw=true should propagate")
        #expect(rows.first { $0.title == "clean" }?.isNsfw == false, "both SFW should be false")
    }
}
