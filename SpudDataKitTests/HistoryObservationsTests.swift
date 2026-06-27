//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import Testing
@testable import SpudDataKit

struct HistoryObservationsTests {
    /// Seeds account + community + creator person and returns the account row id.
    private static func seedGraph(_ db: Database, keychainId: String) throws -> (accountId: Int64, communityId: Int64, personId: Int64) {
        try db.execute(sql: "INSERT INTO instance (actorId, createdAt) VALUES (?, ?)", arguments: ["https://\(keychainId).test", Date()])
        let instanceId = db.lastInsertedRowID
        try db.execute(sql: "INSERT INTO site (instanceId, createdAt, updatedAt) VALUES (?, ?, ?)", arguments: [instanceId, Date(), Date()])
        let siteId = db.lastInsertedRowID
        try db.execute(sql: """
            INSERT INTO person (siteId, personId, name, isAdmin, isBanned, isBotAccount, isDeleted, isLocal, numberOfPosts, numberOfComments, createdAt, updatedAt)
            VALUES (?, 10, 'alice', 0, 0, 0, 0, 0, 0, 0, ?, ?)
            """, arguments: [siteId, Date(), Date()])
        let personId = db.lastInsertedRowID
        try db.execute(sql: """
            INSERT INTO account (siteId, accountKeychainId, isDefault, isServiceAccount, isSignedOutAccountType, createdAt, updatedAt)
            VALUES (?, ?, 0, 0, 0, ?, ?)
            """, arguments: [siteId, keychainId, Date(), Date()])
        let accountId = db.lastInsertedRowID
        try db.execute(sql: """
            INSERT INTO community (accountId, communityId, name, actorId, isHidden, isLocal, isNsfw, isPostingRestrictedToMods, isRemoved, subscribedState, numberOfSubscribers, numberOfPosts, numberOfComments, createdAt, updatedAt)
            VALUES (?, 5, 'programming', 'https://\(keychainId).test/c/programming', 0, 0, 0, 0, 0, 'NotSubscribed', 0, 0, 0, ?, ?)
            """, arguments: [accountId, Date(), Date()])
        let communityId = db.lastInsertedRowID
        return (accountId, communityId, personId)
    }

    /// Inserts a post (and returns its row id) for the given account/community/creator.
    private static func insertPost(_ db: Database, accountId: Int64, communityId: Int64, personId: Int64, serverPostId: Int64, title: String, isSaved: Bool) throws -> Int64 {
        try db.execute(sql: """
            INSERT INTO post (accountId, communityId, creatorId, postId, title, originalPostUrl, score, numberOfUpvotes, numberOfDownvotes, numberOfComments, isRead, isSaved, isHidden, isRemoved, isLocked, isFeaturedCommunity, isFeaturedLocal, isDeleted, published, createdAt, updatedAt)
            VALUES (?, ?, ?, ?, ?, 'https://x.test/post/\(serverPostId)', 7, 7, 0, 3, 0, ?, 0, 0, 0, 0, 0, 0, ?, ?, ?)
            """, arguments: [accountId, communityId, personId, serverPostId, title, isSaved, Date(), Date(), Date()])
        return db.lastInsertedRowID
    }

    private static func insertInteraction(_ db: Database, accountId: Int64, postServerId: Int64, title: String, lastOpenedAt: Date?, lastSeenAt: Date?) throws {
        var record = PostInteractionRecord(accountId: accountId, postServerId: postServerId)
        record.titleSnapshot = title
        record.communityName = "programming"
        record.lastOpenedAt = lastOpenedAt
        record.lastSeenAt = lastSeenAt
        try record.insert(db)
    }

    private static func firstBatch(_ stream: AsyncStream<[PostListRow]>) async -> [PostListRow] {
        for await rows in stream {
            return rows
        }
        return []
    }

    @Test
    func readModeReturnsOnlyOpenedNewestFirst() async throws {
        let t1 = Date(timeIntervalSince1970: 1_000_100)
        let t2 = Date(timeIntervalSince1970: 1_000_200)
        let appDatabase = try AppDatabase.inMemory()
        try await appDatabase.writer.write { db in
            let g = try Self.seedGraph(db, keychainId: "kc-1")
            _ = try Self.insertPost(db, accountId: g.accountId, communityId: g.communityId, personId: g.personId, serverPostId: 1, title: "Opened earlier", isSaved: false)
            _ = try Self.insertPost(db, accountId: g.accountId, communityId: g.communityId, personId: g.personId, serverPostId: 2, title: "Opened later", isSaved: false)
            _ = try Self.insertPost(db, accountId: g.accountId, communityId: g.communityId, personId: g.personId, serverPostId: 3, title: "Only seen", isSaved: false)
            try Self.insertInteraction(db, accountId: g.accountId, postServerId: 1, title: "Opened earlier", lastOpenedAt: t1, lastSeenAt: nil)
            try Self.insertInteraction(db, accountId: g.accountId, postServerId: 2, title: "Opened later", lastOpenedAt: t2, lastSeenAt: nil)
            try Self.insertInteraction(db, accountId: g.accountId, postServerId: 3, title: "Only seen", lastOpenedAt: nil, lastSeenAt: t1)
        }
        let rows = await Self.firstBatch(appDatabase.observeHistoryRows(forKeychainId: "kc-1", mode: .read, searchQuery: nil))
        #expect(rows.map(\.serverPostId) == [2, 1]) // newest opened first; "only seen" excluded
    }

    @Test
    func seenModeReturnsEverythingEncountered() async throws {
        let t1 = Date(timeIntervalSince1970: 1_000_100)
        let t2 = Date(timeIntervalSince1970: 1_000_200)
        let appDatabase = try AppDatabase.inMemory()
        try await appDatabase.writer.write { db in
            let g = try Self.seedGraph(db, keychainId: "kc-1")
            _ = try Self.insertPost(db, accountId: g.accountId, communityId: g.communityId, personId: g.personId, serverPostId: 1, title: "Opened", isSaved: false)
            _ = try Self.insertPost(db, accountId: g.accountId, communityId: g.communityId, personId: g.personId, serverPostId: 3, title: "Only seen", isSaved: false)
            try Self.insertInteraction(db, accountId: g.accountId, postServerId: 1, title: "Opened", lastOpenedAt: t1, lastSeenAt: nil)
            try Self.insertInteraction(db, accountId: g.accountId, postServerId: 3, title: "Only seen", lastOpenedAt: nil, lastSeenAt: t2)
        }
        let rows = await Self.firstBatch(appDatabase.observeHistoryRows(forKeychainId: "kc-1", mode: .seen, searchQuery: nil))
        #expect(Set(rows.map(\.serverPostId)) == [1, 3])
        #expect(rows.first?.serverPostId == 3) // most-recently-encountered first (t2 > t1)
    }

    @Test
    func savedModeReturnsOnlySaved() async throws {
        let t1 = Date(timeIntervalSince1970: 1_000_100)
        let t2 = Date(timeIntervalSince1970: 1_000_200)
        let appDatabase = try AppDatabase.inMemory()
        try await appDatabase.writer.write { db in
            let g = try Self.seedGraph(db, keychainId: "kc-1")
            _ = try Self.insertPost(db, accountId: g.accountId, communityId: g.communityId, personId: g.personId, serverPostId: 1, title: "Saved one", isSaved: true)
            _ = try Self.insertPost(db, accountId: g.accountId, communityId: g.communityId, personId: g.personId, serverPostId: 2, title: "Unsaved", isSaved: false)
            try Self.insertInteraction(db, accountId: g.accountId, postServerId: 1, title: "Saved one", lastOpenedAt: t1, lastSeenAt: nil)
            try Self.insertInteraction(db, accountId: g.accountId, postServerId: 2, title: "Unsaved", lastOpenedAt: t2, lastSeenAt: nil)
        }
        let rows = await Self.firstBatch(appDatabase.observeHistoryRows(forKeychainId: "kc-1", mode: .saved, searchQuery: nil))
        #expect(rows.map(\.serverPostId) == [1])
    }

    @Test
    func searchNarrowsByTitle() async throws {
        let t1 = Date(timeIntervalSince1970: 1_000_100)
        let t2 = Date(timeIntervalSince1970: 1_000_200)
        let appDatabase = try AppDatabase.inMemory()
        try await appDatabase.writer.write { db in
            let g = try Self.seedGraph(db, keychainId: "kc-1")
            _ = try Self.insertPost(db, accountId: g.accountId, communityId: g.communityId, personId: g.personId, serverPostId: 1, title: "Swift Concurrency", isSaved: false)
            _ = try Self.insertPost(db, accountId: g.accountId, communityId: g.communityId, personId: g.personId, serverPostId: 2, title: "Rust ownership", isSaved: false)
            try Self.insertInteraction(db, accountId: g.accountId, postServerId: 1, title: "Swift Concurrency", lastOpenedAt: t1, lastSeenAt: nil)
            try Self.insertInteraction(db, accountId: g.accountId, postServerId: 2, title: "Rust ownership", lastOpenedAt: t2, lastSeenAt: nil)
        }
        let rows = await Self.firstBatch(appDatabase.observeHistoryRows(forKeychainId: "kc-1", mode: .seen, searchQuery: "concurrency"))
        #expect(rows.map(\.serverPostId) == [1])
    }

    @Test
    func accountIsolationIncludingSearch() async throws {
        let t1 = Date(timeIntervalSince1970: 1_000_100)
        let t2 = Date(timeIntervalSince1970: 1_000_200)
        let appDatabase = try AppDatabase.inMemory()
        try await appDatabase.writer.write { db in
            let g1 = try Self.seedGraph(db, keychainId: "kc-1")
            let g2 = try Self.seedGraph(db, keychainId: "kc-2")
            // Same serverPostId and same searchable title in BOTH accounts.
            _ = try Self.insertPost(db, accountId: g1.accountId, communityId: g1.communityId, personId: g1.personId, serverPostId: 1, title: "Swift Concurrency", isSaved: false)
            _ = try Self.insertPost(db, accountId: g2.accountId, communityId: g2.communityId, personId: g2.personId, serverPostId: 1, title: "Swift Concurrency", isSaved: false)
            try Self.insertInteraction(db, accountId: g1.accountId, postServerId: 1, title: "Swift Concurrency", lastOpenedAt: t1, lastSeenAt: nil)
            try Self.insertInteraction(db, accountId: g2.accountId, postServerId: 1, title: "Swift Concurrency", lastOpenedAt: t2, lastSeenAt: nil)
        }
        // Plain query: account 1 sees only its own row (account 2's identical
        // post must not leak).
        let plain = await Self.firstBatch(appDatabase.observeHistoryRows(forKeychainId: "kc-1", mode: .read, searchQuery: nil))
        #expect(plain.count == 1)
        #expect(plain.first?.communityActorId == "https://kc-1.test/c/programming")

        // FTS path: MATCH spans both accounts' tokens, but the accountId filter
        // still restricts results to account 1.
        let searched = await Self.firstBatch(appDatabase.observeHistoryRows(forKeychainId: "kc-1", mode: .seen, searchQuery: "concurrency"))
        #expect(searched.count == 1)
        #expect(searched.first?.communityActorId == "https://kc-1.test/c/programming")
    }
}
