//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import Testing
@testable import SpudDataKit

struct SpotlightContentQueriesTests {
    private static func seedGraph(_ db: Database, keychainId: String, isDefault: Bool) throws -> (accountId: Int64, communityId: Int64, personId: Int64) {
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
            VALUES (?, ?, ?, 0, 0, ?, ?)
            """, arguments: [siteId, keychainId, isDefault, Date(), Date()])
        let accountId = db.lastInsertedRowID
        try db.execute(sql: """
            INSERT INTO community (accountId, communityId, name, actorId, isHidden, isLocal, isNsfw, isPostingRestrictedToMods, isRemoved, subscribedState, numberOfSubscribers, numberOfPosts, numberOfComments, createdAt, updatedAt)
            VALUES (?, 5, 'programming', 'https://\(keychainId).test/c/programming', 0, 0, 0, 0, 0, 'NotSubscribed', 0, 0, 0, ?, ?)
            """, arguments: [accountId, Date(), Date()])
        let communityId = db.lastInsertedRowID
        return (accountId, communityId, personId)
    }

    private static func insertPost(_ db: Database, accountId: Int64, communityId: Int64, personId: Int64, serverPostId: Int64, title: String, isSaved: Bool) throws {
        try db.execute(sql: """
            INSERT INTO post (accountId, communityId, creatorId, postId, title, originalPostUrl, score, numberOfUpvotes, numberOfDownvotes, numberOfComments, isRead, isSaved, isHidden, isRemoved, isLocked, isFeaturedCommunity, isFeaturedLocal, isDeleted, published, createdAt, updatedAt)
            VALUES (?, ?, ?, ?, ?, 'https://x.test/post/\(serverPostId)', 7, 7, 0, 3, 0, ?, 0, 0, 0, 0, 0, 0, ?, ?, ?)
            """, arguments: [accountId, communityId, personId, serverPostId, title, isSaved, Date(), Date(), Date()])
    }

    private static func insertInteraction(_ db: Database, accountId: Int64, postServerId: Int64, title: String, lastOpenedAt: Date?) throws {
        var record = PostInteractionRecord(accountId: accountId, postServerId: postServerId)
        record.titleSnapshot = title
        record.communityName = "programming"
        record.lastOpenedAt = lastOpenedAt
        try record.insert(db)
    }

    @Test
    func indexableRows_returnsSavedAndRecentOpened() async throws {
        let appDatabase = try AppDatabase.inMemory()
        try await appDatabase.writer.write { db in
            let g = try Self.seedGraph(db, keychainId: "kc-1", isDefault: true)
            // 1: saved but never opened -> included (saved)
            try Self.insertPost(db, accountId: g.accountId, communityId: g.communityId, personId: g.personId, serverPostId: 1, title: "Saved", isSaved: true)
            try Self.insertInteraction(db, accountId: g.accountId, postServerId: 1, title: "Saved", lastOpenedAt: nil)
            // 2: opened but not saved -> included (recent)
            try Self.insertPost(db, accountId: g.accountId, communityId: g.communityId, personId: g.personId, serverPostId: 2, title: "Opened", isSaved: false)
            try Self.insertInteraction(db, accountId: g.accountId, postServerId: 2, title: "Opened", lastOpenedAt: Date(timeIntervalSince1970: 1_000_000))
            // 3: only seen (never opened, not saved) -> excluded
            try Self.insertPost(db, accountId: g.accountId, communityId: g.communityId, personId: g.personId, serverPostId: 3, title: "OnlySeen", isSaved: false)
            try Self.insertInteraction(db, accountId: g.accountId, postServerId: 3, title: "OnlySeen", lastOpenedAt: nil)
        }
        let rows = appDatabase.indexableContentRowsSync(forKeychainId: "kc-1", limit: 100)
        #expect(Set(rows.map(\.serverPostId)) == [1, 2])
        let saved = rows.first { $0.serverPostId == 1 }
        #expect(saved?.title == "Saved")
        #expect(saved?.originalPostUrl == "https://x.test/post/1")
        #expect(saved?.communityName == "programming")
    }

    @Test
    func indexableRowsForDefaultAccount_resolvesDefault() async throws {
        let appDatabase = try AppDatabase.inMemory()
        try await appDatabase.writer.write { db in
            let g = try Self.seedGraph(db, keychainId: "kc-default", isDefault: true)
            try Self.insertPost(db, accountId: g.accountId, communityId: g.communityId, personId: g.personId, serverPostId: 1, title: "Saved", isSaved: true)
            try Self.insertInteraction(db, accountId: g.accountId, postServerId: 1, title: "Saved", lastOpenedAt: nil)
        }
        let rows = appDatabase.indexableContentRowsForDefaultAccountSync(limit: 100)
        #expect(rows.map(\.serverPostId) == [1])
    }

    /// Spotlight indexing must be scoped to a single account. A saved post that
    /// belongs to a different account (kc-2) must NOT appear in the index for
    /// kc-1, even when both accounts exist in the same database.
    @Test
    func indexableRows_accountIsolation_doesNotLeakCrossAccount() async throws {
        let appDatabase = try AppDatabase.inMemory()
        try await appDatabase.writer.write { db in
            // Account 1 — one saved post.
            let g1 = try Self.seedGraph(db, keychainId: "kc-1", isDefault: true)
            try Self.insertPost(db, accountId: g1.accountId, communityId: g1.communityId, personId: g1.personId, serverPostId: 101, title: "Account1Post", isSaved: true)
            try Self.insertInteraction(db, accountId: g1.accountId, postServerId: 101, title: "Account1Post", lastOpenedAt: nil)

            // Account 2 — one saved post (must not bleed into kc-1's index).
            let g2 = try Self.seedGraph(db, keychainId: "kc-2", isDefault: false)
            try Self.insertPost(db, accountId: g2.accountId, communityId: g2.communityId, personId: g2.personId, serverPostId: 202, title: "Account2Post", isSaved: true)
            try Self.insertInteraction(db, accountId: g2.accountId, postServerId: 202, title: "Account2Post", lastOpenedAt: nil)
        }
        let rows = appDatabase.indexableContentRowsSync(forKeychainId: "kc-1", limit: 100)
        #expect(rows.map(\.serverPostId) == [101])
        #expect(!(rows.contains(where: { $0.serverPostId == 202 })), "account kc-2 post must not appear in kc-1 index")
    }
}
