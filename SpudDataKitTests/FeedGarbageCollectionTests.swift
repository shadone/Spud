//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import XCTest
@testable import SpudDataKit

/// Tests for `AppDatabase.pruneStaleFeedRows(olderThan:)`.
///
/// Each test seeds data directly into an in-memory database to avoid relying
/// on the full LemmyService import pipeline.
final class FeedGarbageCollectionTests: XCTestCase {
    private var appDatabase: AppDatabase!

    override func setUpWithError() throws {
        appDatabase = try AppDatabase.inMemory()
    }

    override func tearDown() {
        appDatabase = nil
    }

    // MARK: - Seed helpers

    /// Inserts the minimum required graph (instance -> site -> account) and
    /// returns the account row id. Mirrors the pattern in
    /// `PostInteractionWritesTests.seedAccount`.
    @discardableResult
    private func seedAccount(keychainId: String = "kc-1") async throws -> Int64 {
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

    /// Reads the site row id from the database (used after seedAccount).
    private func fetchSiteId() async throws -> Int64 {
        try await appDatabase.writer.read { db in
            try Int64.fetchOne(db, sql: "SELECT id FROM site LIMIT 1") ?? 0
        }
    }

    /// Inserts a person + community row required by the `post` FK constraints.
    private func seedPostDependencies(accountId: Int64, siteId: Int64) async throws -> (communityId: Int64, personId: Int64) {
        let now = Date()
        return try await appDatabase.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO person
                        (siteId, personId, isAdmin, isBanned, isBotAccount, isDeleted, isLocal,
                         numberOfPosts, numberOfComments, createdAt, updatedAt)
                    VALUES (?, 1, 0, 0, 0, 0, 1, 0, 0, ?, ?)
                    """,
                arguments: [siteId, now, now]
            )
            let personRowId = db.lastInsertedRowID

            try db.execute(
                sql: """
                    INSERT INTO community
                        (accountId, communityId, isHidden, isLocal, isNsfw, isPostingRestrictedToMods,
                         isRemoved, subscribedState, numberOfSubscribers, numberOfPosts,
                         numberOfComments, createdAt, updatedAt)
                    VALUES (?, 1, 0, 1, 0, 0, 0, 'NotSubscribed', 0, 0, 0, ?, ?)
                    """,
                arguments: [accountId, now, now]
            )
            let communityRowId = db.lastInsertedRowID

            return (communityRowId, personRowId)
        }
    }

    /// Inserts a minimal `post` row and returns its row id.
    private func seedPost(accountId: Int64, communityId: Int64, personId: Int64, postId: Int64 = 1) async throws -> Int64 {
        let now = Date()
        return try await appDatabase.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO post
                        (accountId, communityId, creatorId, postId, title, originalPostUrl,
                         score, numberOfUpvotes, numberOfDownvotes, numberOfComments,
                         isRead, isSaved, isHidden, isRemoved, isLocked,
                         isFeaturedCommunity, isFeaturedLocal, isDeleted,
                         published, createdAt, updatedAt)
                    VALUES (?, ?, ?, ?, ?, ?, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, ?, ?, ?)
                    """,
                arguments: [
                    accountId,
                    communityId,
                    personId,
                    postId,
                    "Test post \(postId)",
                    "https://example.com/post/\(postId)",
                    now,
                    now,
                    now,
                ]
            )
            return db.lastInsertedRowID
        }
    }

    /// Inserts a feed row with the given `createdAt` and returns its row id.
    private func seedFeed(accountId: Int64, createdAt: Date, feedKey: String? = nil) async throws -> Int64 {
        try await appDatabase.writer.write { db in
            let key = feedKey ?? UUID().uuidString
            var record = FeedRecord(
                accountId: accountId,
                feedKey: key,
                savedOnly: false,
                sortType: "Hot",
                createdAt: createdAt
            )
            try record.insert(db)
            return record.id!
        }
    }

    /// Inserts a page row for the given feed and returns its row id.
    private func seedPage(feedId: Int64) async throws -> Int64 {
        try await appDatabase.writer.write { db in
            var record = PageRecord(feedId: feedId, position: 0, createdAt: Date())
            try record.insert(db)
            return record.id!
        }
    }

    /// Inserts a pageElement row and returns its row id.
    private func seedPageElement(pageId: Int64, postId: Int64) async throws -> Int64 {
        try await appDatabase.writer.write { db in
            var record = PageElementRecord(pageId: pageId, postId: postId, position: 0)
            try record.insert(db)
            return record.id!
        }
    }

    // MARK: - Count helpers

    private func feedCount() async throws -> Int {
        try await appDatabase.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM feed") ?? 0
        }
    }

    private func feedExists(id: Int64) async throws -> Bool {
        try await appDatabase.writer.read { db in
            try (Int.fetchOne(db, sql: "SELECT COUNT(*) FROM feed WHERE id = ?", arguments: [id]) ?? 0) > 0
        }
    }

    private func pageExists(id: Int64) async throws -> Bool {
        try await appDatabase.writer.read { db in
            try (Int.fetchOne(db, sql: "SELECT COUNT(*) FROM page WHERE id = ?", arguments: [id]) ?? 0) > 0
        }
    }

    private func pageElementExists(id: Int64) async throws -> Bool {
        try await appDatabase.writer.read { db in
            try (Int.fetchOne(db, sql: "SELECT COUNT(*) FROM pageElement WHERE id = ?", arguments: [id]) ?? 0) > 0
        }
    }

    private func postExists(id: Int64) async throws -> Bool {
        try await appDatabase.writer.read { db in
            try (Int.fetchOne(db, sql: "SELECT COUNT(*) FROM post WHERE id = ?", arguments: [id]) ?? 0) > 0
        }
    }

    // MARK: - Tests

    /// Seeds an old feed (1 hour ago) with a page + pageElement referencing a
    /// shared post, and a recent feed (right now) with its own page +
    /// pageElement. Calls `pruneStaleFeedRows(olderThan: 300)` and asserts:
    /// - the old feed, its page, and its pageElement are gone
    /// - the recent feed + its page + pageElement remain
    /// - the shared post row still exists (was NOT cascaded away)
    func testPrunesFeedsOlderThanCutoffWithPagesAndElements() async throws {
        let accountId = try await seedAccount()
        let siteId = try await fetchSiteId()
        let deps = try await seedPostDependencies(accountId: accountId, siteId: siteId)
        let postRowId = try await seedPost(accountId: accountId, communityId: deps.communityId, personId: deps.personId)

        // "old" feed: created 1 hour ago, well past the 300 s cutoff.
        let oldCreatedAt = Date().addingTimeInterval(-3600)
        let oldFeedId = try await seedFeed(accountId: accountId, createdAt: oldCreatedAt)
        let oldPageId = try await seedPage(feedId: oldFeedId)
        let oldElementId = try await seedPageElement(pageId: oldPageId, postId: postRowId)

        // "recent" feed: created right now, not past the cutoff.
        let recentFeedId = try await seedFeed(accountId: accountId, createdAt: Date())
        let recentPageId = try await seedPage(feedId: recentFeedId)
        let recentElementId = try await seedPageElement(pageId: recentPageId, postId: postRowId)

        _ = try await appDatabase.pruneStaleFeedRows(olderThan: 300)

        let oldFeedGone = try await feedExists(id: oldFeedId)
        let oldPageGone = try await pageExists(id: oldPageId)
        let oldElementGone = try await pageElementExists(id: oldElementId)
        let recentFeedStillThere = try await feedExists(id: recentFeedId)
        let recentPageStillThere = try await pageExists(id: recentPageId)
        let recentElementStillThere = try await pageElementExists(id: recentElementId)
        let postStillThere = try await postExists(id: postRowId)

        XCTAssertFalse(oldFeedGone, "old feed should have been pruned")
        XCTAssertFalse(oldPageGone, "old page should have been pruned")
        XCTAssertFalse(oldElementGone, "old pageElement should have been pruned")
        XCTAssertTrue(recentFeedStillThere, "recent feed should remain")
        XCTAssertTrue(recentPageStillThere, "recent page should remain")
        XCTAssertTrue(recentElementStillThere, "recent pageElement should remain")
        XCTAssertTrue(postStillThere, "shared post row must NOT be deleted by feed GC")
    }

    /// The return value must equal the number of stale feed rows deleted.
    func testReturnsDeletedFeedCount() async throws {
        let accountId = try await seedAccount()

        let oldCreatedAt = Date().addingTimeInterval(-3600)
        _ = try await seedFeed(accountId: accountId, createdAt: oldCreatedAt, feedKey: "old-1")
        _ = try await seedFeed(accountId: accountId, createdAt: oldCreatedAt, feedKey: "old-2")
        _ = try await seedFeed(accountId: accountId, createdAt: Date(), feedKey: "recent-1")

        let deleted = try await appDatabase.pruneStaleFeedRows(olderThan: 300)
        let remaining = try await feedCount()

        XCTAssertEqual(deleted, 2, "should report exactly 2 deleted feed rows")
        XCTAssertEqual(remaining, 1, "one recent feed should remain")
    }

    /// When no feeds are older than the cutoff, nothing is deleted and 0 is returned.
    func testKeepsAllFeedsWhenNoneOlderThanCutoff() async throws {
        let accountId = try await seedAccount()

        // All feeds created "now" - well within 300 s cutoff.
        _ = try await seedFeed(accountId: accountId, createdAt: Date(), feedKey: "recent-a")
        _ = try await seedFeed(accountId: accountId, createdAt: Date(), feedKey: "recent-b")

        let deleted = try await appDatabase.pruneStaleFeedRows(olderThan: 300)
        let remaining = try await feedCount()

        XCTAssertEqual(deleted, 0, "should delete nothing when all feeds are recent")
        XCTAssertEqual(remaining, 2, "both recent feeds should remain")
    }
}
