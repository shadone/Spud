//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import Testing
@testable import SpudDataKit

/// Tests for the Summary dashboard data layer:
/// - `AppDatabase.countSavedItems(accountId:)`
/// - `AppDatabase.countReadItems(accountId:)`
/// - `AppDatabase.countVoteEvents(accountId:)`
/// - `AppDatabase.countFollowedCommunities(accountId:)`
/// - `AppDatabase.observeSummaryStats(accountId:personRowId:)`
///
/// Per-test `AppDatabase.inMemory()` instances are isolated; no `.serialized` needed.
struct SummaryStatsTests {
    // MARK: - Helpers

    /// Seeds instance → site → account. Returns accountId and siteId.
    private static func seedAccount(
        _ db: Database,
        host: String = "test.instance"
    ) throws -> (accountId: Int64, siteId: Int64) {
        try db.execute(
            sql: "INSERT INTO instance (actorId, createdAt) VALUES (?, ?)",
            arguments: ["https://\(host)", Date()]
        )
        let instanceId = db.lastInsertedRowID
        try db.execute(
            sql: "INSERT INTO site (instanceId, createdAt, updatedAt) VALUES (?, ?, ?)",
            arguments: [instanceId, Date(), Date()]
        )
        let siteId = db.lastInsertedRowID
        try db.execute(
            sql: """
                INSERT INTO account (siteId, accountKeychainId, isDefault, isServiceAccount,
                                     isSignedOutAccountType, createdAt, updatedAt)
                VALUES (?, ?, 1, 0, 0, ?, ?)
                """,
            arguments: [siteId, "kc-\(host)", Date(), Date()]
        )
        let accountId = db.lastInsertedRowID
        return (accountId, siteId)
    }

    /// Seeds a person row for the given siteId. Returns personRowId.
    private static func seedPerson(
        _ db: Database,
        siteId: Int64,
        name: String = "alice",
        displayName: String? = nil,
        numberOfPosts: Int64 = 0,
        numberOfComments: Int64 = 0,
        personCreatedDate: Date? = nil
    ) throws -> Int64 {
        try db.execute(
            sql: """
                INSERT INTO person (siteId, personId, name, displayName, isAdmin, isBanned,
                                    isBotAccount, isDeleted, isLocal, numberOfPosts,
                                    numberOfComments, personCreatedDate, createdAt, updatedAt)
                VALUES (?, 1, ?, ?, 0, 0, 0, 0, 0, ?, ?, ?, ?, ?)
                """,
            arguments: [
                siteId,
                name,
                displayName,
                numberOfPosts,
                numberOfComments,
                personCreatedDate,
                Date(),
                Date(),
            ]
        )
        return db.lastInsertedRowID
    }

    /// Seeds a community row for the account. Returns communityRowId.
    private static func seedCommunity(
        _ db: Database,
        accountId: Int64,
        serverCommunityId: Int64? = nil
    ) throws -> Int64 {
        let tag = serverCommunityId ?? accountId
        try db.execute(
            sql: """
                INSERT INTO community (accountId, communityId, name, actorId, isHidden, isLocal, isNsfw,
                                       isPostingRestrictedToMods, isRemoved, subscribedState,
                                       numberOfSubscribers, numberOfPosts, numberOfComments, createdAt, updatedAt)
                VALUES (?, ?, 'c\(tag)', 'https://test.instance/c/c\(tag)', 0, 0, 0, 0, 0, 'NotSubscribed', 0, 0, 0, ?, ?)
                """,
            arguments: [accountId, tag, Date(), Date()]
        )
        return db.lastInsertedRowID
    }

    private static func insertPost(
        _ db: Database,
        accountId: Int64,
        communityId: Int64,
        personId: Int64,
        serverPostId: Int64,
        isSaved: Bool = false
    ) throws -> Int64 {
        try db.execute(
            sql: """
                INSERT INTO post (accountId, communityId, creatorId, postId, title, originalPostUrl,
                                  score, numberOfUpvotes, numberOfDownvotes, numberOfComments,
                                  isRead, isSaved, isHidden, isRemoved, isLocked,
                                  isFeaturedCommunity, isFeaturedLocal, isDeleted, published, createdAt, updatedAt)
                VALUES (?, ?, ?, ?, 'Post \(serverPostId)', 'https://\(serverPostId).test',
                        0, 0, 0, 0, 0, ?, 0, 0, 0, 0, 0, 0, ?, ?, ?)
                """,
            arguments: [accountId, communityId, personId, serverPostId, isSaved, Date(), Date(), Date()]
        )
        return db.lastInsertedRowID
    }

    private static func insertComment(
        _ db: Database,
        postRowId: Int64,
        personId: Int64,
        localCommentId: Int64,
        isSaved: Bool = false
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO comment (postId, creatorId, localCommentId, body, score,
                                     numberOfUpvotes, numberOfDownvotes, isSaved, isRemoved,
                                     isDistinguished, isDeleted, isCreatorModerator, isCreatorAdmin,
                                     isCreatorBannedFromCommunity, isCreatorBlocked,
                                     originalCommentUrl, published, createdAt, updatedAt)
                VALUES (?, ?, ?, 'body', 0, 0, 0, ?, 0, 0, 0, 0, 0, 0, 0,
                        'https://\(localCommentId).test/comment', ?, ?, ?)
                """,
            arguments: [postRowId, personId, localCommentId, isSaved, Date(), Date(), Date()]
        )
    }

    private static func insertInteraction(
        _ db: Database,
        accountId: Int64,
        postServerId: Int64,
        lastOpenedAt: Date?
    ) throws {
        var record = PostInteractionRecord(accountId: accountId, postServerId: postServerId)
        record.titleSnapshot = "Post \(postServerId)"
        record.lastOpenedAt = lastOpenedAt
        try record.insert(db)
    }

    private static func firstBatch<T>(_ stream: AsyncStream<T>) async -> T? {
        for await value in stream {
            return value
        }
        return nil
    }

    // MARK: - countSavedItems

    @Test
    func countSavedItems_zeroWhenEmpty() async throws {
        let db = try AppDatabase.inMemory()
        let accountId = try await db.writer.write { try Self.seedAccount($0).accountId }
        let count = try db.countSavedItems(accountId: accountId)
        #expect(count == 0)
    }

    @Test
    func countSavedItems_countsSavedPosts() async throws {
        let db = try AppDatabase.inMemory()
        let accountId = try await db.writer.write { db -> Int64 in
            let (accId, siteId) = try Self.seedAccount(db)
            let personId = try Self.seedPerson(db, siteId: siteId)
            let commId = try Self.seedCommunity(db, accountId: accId)
            _ = try Self.insertPost(db, accountId: accId, communityId: commId, personId: personId, serverPostId: 1, isSaved: true)
            _ = try Self.insertPost(db, accountId: accId, communityId: commId, personId: personId, serverPostId: 2, isSaved: false)
            return accId
        }
        let count = try db.countSavedItems(accountId: accountId)
        #expect(count == 1)
    }

    @Test
    func countSavedItems_countsSavedComments() async throws {
        let db = try AppDatabase.inMemory()
        let accountId = try await db.writer.write { db -> Int64 in
            let (accId, siteId) = try Self.seedAccount(db)
            let personId = try Self.seedPerson(db, siteId: siteId)
            let commId = try Self.seedCommunity(db, accountId: accId)
            let postRowId = try Self.insertPost(db, accountId: accId, communityId: commId, personId: personId, serverPostId: 10)
            try Self.insertComment(db, postRowId: postRowId, personId: personId, localCommentId: 100, isSaved: true)
            try Self.insertComment(db, postRowId: postRowId, personId: personId, localCommentId: 101, isSaved: false)
            return accId
        }
        let count = try db.countSavedItems(accountId: accountId)
        #expect(count == 1)
    }

    @Test
    func countSavedItems_combinesPostsAndComments() async throws {
        let db = try AppDatabase.inMemory()
        let accountId = try await db.writer.write { db -> Int64 in
            let (accId, siteId) = try Self.seedAccount(db)
            let personId = try Self.seedPerson(db, siteId: siteId)
            let commId = try Self.seedCommunity(db, accountId: accId)
            _ = try Self.insertPost(db, accountId: accId, communityId: commId, personId: personId, serverPostId: 1, isSaved: true)
            let postRowId = try Self.insertPost(db, accountId: accId, communityId: commId, personId: personId, serverPostId: 2)
            try Self.insertComment(db, postRowId: postRowId, personId: personId, localCommentId: 201, isSaved: true)
            return accId
        }
        let count = try db.countSavedItems(accountId: accountId)
        #expect(count == 2)
    }

    @Test
    func countSavedItems_accountIsolation() async throws {
        let db = try AppDatabase.inMemory()
        let (accA, accB) = try await db.writer.write { db -> (Int64, Int64) in
            let (accIdA, siteIdA) = try Self.seedAccount(db, host: "alpha.test")
            let personA = try Self.seedPerson(db, siteId: siteIdA)
            let commA = try Self.seedCommunity(db, accountId: accIdA)
            _ = try Self.insertPost(db, accountId: accIdA, communityId: commA, personId: personA, serverPostId: 1, isSaved: true)

            let (accIdB, siteIdB) = try Self.seedAccount(db, host: "beta.test")
            let personB = try Self.seedPerson(db, siteId: siteIdB)
            let commB = try Self.seedCommunity(db, accountId: accIdB)
            _ = try Self.insertPost(db, accountId: accIdB, communityId: commB, personId: personB, serverPostId: 2, isSaved: true)
            _ = try Self.insertPost(db, accountId: accIdB, communityId: commB, personId: personB, serverPostId: 3, isSaved: true)
            return (accIdA, accIdB)
        }
        #expect(try db.countSavedItems(accountId: accA) == 1)
        #expect(try db.countSavedItems(accountId: accB) == 2)
    }

    // MARK: - countReadItems

    @Test
    func countReadItems_zeroWhenEmpty() async throws {
        let db = try AppDatabase.inMemory()
        let accountId = try await db.writer.write { try Self.seedAccount($0).accountId }
        let count = try db.countReadItems(accountId: accountId)
        #expect(count == 0)
    }

    @Test
    func countReadItems_onlyCountsOpenedInteractions() async throws {
        let db = try AppDatabase.inMemory()
        let t = Date(timeIntervalSince1970: 1_000_000)
        let accountId = try await db.writer.write { db -> Int64 in
            let (accId, _) = try Self.seedAccount(db)
            // opened
            try Self.insertInteraction(db, accountId: accId, postServerId: 1, lastOpenedAt: t)
            // only seen, not opened
            try Self.insertInteraction(db, accountId: accId, postServerId: 2, lastOpenedAt: nil)
            return accId
        }
        let count = try db.countReadItems(accountId: accountId)
        #expect(count == 1)
    }

    @Test
    func countReadItems_accountIsolation() async throws {
        let db = try AppDatabase.inMemory()
        let t = Date(timeIntervalSince1970: 1_000_000)
        let (accA, accB) = try await db.writer.write { db -> (Int64, Int64) in
            let (accIdA, _) = try Self.seedAccount(db, host: "alpha.test")
            let (accIdB, _) = try Self.seedAccount(db, host: "beta.test")
            try Self.insertInteraction(db, accountId: accIdA, postServerId: 1, lastOpenedAt: t)
            try Self.insertInteraction(db, accountId: accIdB, postServerId: 2, lastOpenedAt: t)
            try Self.insertInteraction(db, accountId: accIdB, postServerId: 3, lastOpenedAt: t)
            return (accIdA, accIdB)
        }
        #expect(try db.countReadItems(accountId: accA) == 1)
        #expect(try db.countReadItems(accountId: accB) == 2)
    }

    // MARK: - countVoteEvents

    @Test
    func countVoteEvents_zeroWhenEmpty() async throws {
        let db = try AppDatabase.inMemory()
        let accountId = try await db.writer.write { try Self.seedAccount($0).accountId }
        let count = try db.countVoteEvents(accountId: accountId)
        #expect(count == 0)
    }

    @Test
    func countVoteEvents_countsPerAccount() async throws {
        let db = try AppDatabase.inMemory()
        let accountId = try await db.writer.write { try Self.seedAccount($0).accountId }
        try await db.upsertVoteEvent(
            accountId: accountId,
            entityType: "post",
            entityServerId: 1,
            voteAction: 1,
            votedAt: 1_000_000,
            title: nil,
            body: nil,
            communityName: nil,
            communityActorId: nil,
            thumbnailUrl: nil,
            score: nil
        )
        try await db.upsertVoteEvent(
            accountId: accountId,
            entityType: "post",
            entityServerId: 2,
            voteAction: 0,
            votedAt: 1_000_001,
            title: nil,
            body: nil,
            communityName: nil,
            communityActorId: nil,
            thumbnailUrl: nil,
            score: nil
        )
        let count = try db.countVoteEvents(accountId: accountId)
        #expect(count == 2)
    }

    @Test
    func countVoteEvents_accountIsolation() async throws {
        let db = try AppDatabase.inMemory()
        let (accA, accB) = try await db.writer.write { db -> (Int64, Int64) in
            let (a, _) = try Self.seedAccount(db, host: "alpha.test")
            let (b, _) = try Self.seedAccount(db, host: "beta.test")
            return (a, b)
        }
        try await db.upsertVoteEvent(
            accountId: accA, entityType: "post", entityServerId: 10, voteAction: 1,
            votedAt: 1_000_000, title: nil, body: nil, communityName: nil,
            communityActorId: nil, thumbnailUrl: nil, score: nil
        )
        try await db.upsertVoteEvent(
            accountId: accB, entityType: "post", entityServerId: 20, voteAction: 1,
            votedAt: 1_000_001, title: nil, body: nil, communityName: nil,
            communityActorId: nil, thumbnailUrl: nil, score: nil
        )
        try await db.upsertVoteEvent(
            accountId: accB, entityType: "post", entityServerId: 21, voteAction: 0,
            votedAt: 1_000_002, title: nil, body: nil, communityName: nil,
            communityActorId: nil, thumbnailUrl: nil, score: nil
        )
        #expect(try db.countVoteEvents(accountId: accA) == 1)
        #expect(try db.countVoteEvents(accountId: accB) == 2)
    }

    // MARK: - countFollowedCommunities

    @Test
    func countFollowedCommunities_zeroWhenNone() async throws {
        let db = try AppDatabase.inMemory()
        let accountId = try await db.writer.write { try Self.seedAccount($0).accountId }
        let count = try db.countFollowedCommunities(accountId: accountId)
        #expect(count == 0)
    }

    @Test
    func countFollowedCommunities_countsRows() async throws {
        let db = try AppDatabase.inMemory()
        let accountId = try await db.writer.write { db -> Int64 in
            let (accId, _) = try Self.seedAccount(db)
            let c1 = try Self.seedCommunity(db, accountId: accId)
            // communityId column references community.id (the row PK)
            try db.execute(
                sql: "INSERT INTO accountFollowedCommunity (accountId, communityId) VALUES (?, ?)",
                arguments: [accId, c1]
            )
            return accId
        }
        let count = try db.countFollowedCommunities(accountId: accountId)
        #expect(count == 1)
    }

    @Test
    func countFollowedCommunities_accountIsolation() async throws {
        let db = try AppDatabase.inMemory()
        let (accA, accB) = try await db.writer.write { db -> (Int64, Int64) in
            let (accIdA, _) = try Self.seedAccount(db, host: "alpha.test")
            let (accIdB, _) = try Self.seedAccount(db, host: "beta.test")
            let c1 = try Self.seedCommunity(db, accountId: accIdA)
            let c2 = try Self.seedCommunity(db, accountId: accIdB, serverCommunityId: 201)
            let c3 = try Self.seedCommunity(db, accountId: accIdB, serverCommunityId: 202)
            try db.execute(
                sql: "INSERT INTO accountFollowedCommunity (accountId, communityId) VALUES (?, ?)",
                arguments: [accIdA, c1]
            )
            try db.execute(
                sql: "INSERT INTO accountFollowedCommunity (accountId, communityId) VALUES (?, ?)",
                arguments: [accIdB, c2]
            )
            try db.execute(
                sql: "INSERT INTO accountFollowedCommunity (accountId, communityId) VALUES (?, ?)",
                arguments: [accIdB, c3]
            )
            return (accIdA, accIdB)
        }
        #expect(try db.countFollowedCommunities(accountId: accA) == 1)
        #expect(try db.countFollowedCommunities(accountId: accB) == 2)
    }

    // MARK: - observeSummaryStats — tile shape

    @Test
    func observeSummaryStats_yieldsSixTiles() async throws {
        let db = try AppDatabase.inMemory()
        let (accountId, personRowId) = try await db.writer.write { db -> (Int64, Int64) in
            let (accId, siteId) = try Self.seedAccount(db)
            let pId = try Self.seedPerson(db, siteId: siteId)
            return (accId, pId)
        }
        let stats = await Self.firstBatch(db.observeSummaryStats(accountId: accountId, personRowId: personRowId))
        let tiles = try #require(stats).tiles
        #expect(tiles.count == 6) // swiftformat:disable:previous isEmpty
    }

    @Test
    func observeSummaryStats_tileOrder() async throws {
        let db = try AppDatabase.inMemory()
        let (accountId, personRowId) = try await db.writer.write { db -> (Int64, Int64) in
            let (accId, siteId) = try Self.seedAccount(db)
            let pId = try Self.seedPerson(db, siteId: siteId)
            return (accId, pId)
        }
        let stats = try #require(await Self.firstBatch(db.observeSummaryStats(accountId: accountId, personRowId: personRowId)))
        let keys = stats.tiles.map(\.key)
        #expect(keys == ["posts", "comments", "saved", "votes", "communities", "read"])
    }

    @Test
    func observeSummaryStats_tileSources() async throws {
        let db = try AppDatabase.inMemory()
        let (accountId, personRowId) = try await db.writer.write { db -> (Int64, Int64) in
            let (accId, siteId) = try Self.seedAccount(db)
            let pId = try Self.seedPerson(db, siteId: siteId)
            return (accId, pId)
        }
        let stats = try #require(await Self.firstBatch(db.observeSummaryStats(accountId: accountId, personRowId: personRowId)))
        let byKey: [String: SummaryStat.Source] = Dictionary(uniqueKeysWithValues: stats.tiles.map { ($0.key, $0.source) })
        #expect(byKey["posts"] == .server)
        #expect(byKey["comments"] == .server)
        #expect(byKey["saved"] == .local)
        #expect(byKey["votes"] == .forward)
        #expect(byKey["communities"] == .server)
        #expect(byKey["read"] == .local)
    }

    @Test
    func observeSummaryStats_votesTileHasNewNote() async throws {
        let db = try AppDatabase.inMemory()
        let (accountId, personRowId) = try await db.writer.write { db -> (Int64, Int64) in
            let (accId, siteId) = try Self.seedAccount(db)
            let pId = try Self.seedPerson(db, siteId: siteId)
            return (accId, pId)
        }
        let stats = try #require(await Self.firstBatch(db.observeSummaryStats(accountId: accountId, personRowId: personRowId)))
        let votesTile = try #require(stats.tiles.first { $0.key == "votes" })
        #expect(votesTile.source == .forward)
        #expect(votesTile.note == "new")
    }

    @Test
    func observeSummaryStats_votesTileShowsZeroWhenEmpty() async throws {
        let db = try AppDatabase.inMemory()
        let (accountId, personRowId) = try await db.writer.write { db -> (Int64, Int64) in
            let (accId, siteId) = try Self.seedAccount(db)
            let pId = try Self.seedPerson(db, siteId: siteId)
            return (accId, pId)
        }
        let stats = try #require(await Self.firstBatch(db.observeSummaryStats(accountId: accountId, personRowId: personRowId)))
        let votesTile = try #require(stats.tiles.first { $0.key == "votes" })
        #expect(votesTile.value == "0")
    }

    // MARK: - observeSummaryStats — identity fields

    @Test
    func observeSummaryStats_usesDisplayNameWhenSet() async throws {
        let db = try AppDatabase.inMemory()
        let (accountId, personRowId) = try await db.writer.write { db -> (Int64, Int64) in
            let (accId, siteId) = try Self.seedAccount(db)
            let pId = try Self.seedPerson(db, siteId: siteId, name: "alice", displayName: "Alice Wonderland")
            return (accId, pId)
        }
        let stats = try #require(await Self.firstBatch(db.observeSummaryStats(accountId: accountId, personRowId: personRowId)))
        #expect(stats.name == "Alice Wonderland")
    }

    @Test
    func observeSummaryStats_fallsBackToNameWhenNoDisplayName() async throws {
        let db = try AppDatabase.inMemory()
        let (accountId, personRowId) = try await db.writer.write { db -> (Int64, Int64) in
            let (accId, siteId) = try Self.seedAccount(db)
            let pId = try Self.seedPerson(db, siteId: siteId, name: "alice", displayName: nil)
            return (accId, pId)
        }
        let stats = try #require(await Self.firstBatch(db.observeSummaryStats(accountId: accountId, personRowId: personRowId)))
        #expect(stats.name == "alice")
    }

    @Test
    func observeSummaryStats_emptyJoinedAndCakeDayWhenNoPersonCreatedDate() async throws {
        let db = try AppDatabase.inMemory()
        let (accountId, personRowId) = try await db.writer.write { db -> (Int64, Int64) in
            let (accId, siteId) = try Self.seedAccount(db)
            let pId = try Self.seedPerson(db, siteId: siteId, personCreatedDate: nil)
            return (accId, pId)
        }
        let stats = try #require(await Self.firstBatch(db.observeSummaryStats(accountId: accountId, personRowId: personRowId)))
        #expect(stats.joined.isEmpty)
        #expect(stats.cakeDay.isEmpty)
    }

    @Test
    func observeSummaryStats_populatesJoinedAndCakeDayFromPersonCreatedDate() async throws {
        let createdDate = Date(timeIntervalSince1970: 1_000_000) // historical date
        let db = try AppDatabase.inMemory()
        let (accountId, personRowId) = try await db.writer.write { db -> (Int64, Int64) in
            let (accId, siteId) = try Self.seedAccount(db)
            let pId = try Self.seedPerson(db, siteId: siteId, personCreatedDate: createdDate)
            return (accId, pId)
        }
        let stats = try #require(await Self.firstBatch(db.observeSummaryStats(accountId: accountId, personRowId: personRowId)))
        // joined should be a non-empty relative string (PersonFormatter.string)
        #expect(!stats.joined.isEmpty)
        // cakeDay should be a non-empty absolute date string (PersonFormatter.cakeDayString)
        #expect(!stats.cakeDay.isEmpty)
        // Sanity: cakeDay is distinct from joined (one is relative, one is absolute)
        #expect(stats.joined != stats.cakeDay)
    }

    // MARK: - observeSummaryStats — server-sourced karma

    @Test
    func observeSummaryStats_reflectsServerPostAndCommentKarma() async throws {
        let db = try AppDatabase.inMemory()
        let (accountId, personRowId) = try await db.writer.write { db -> (Int64, Int64) in
            let (accId, siteId) = try Self.seedAccount(db)
            let pId = try Self.seedPerson(db, siteId: siteId, numberOfPosts: 42, numberOfComments: 1337)
            return (accId, pId)
        }
        let stats = try #require(await Self.firstBatch(db.observeSummaryStats(accountId: accountId, personRowId: personRowId)))
        let postsTile = try #require(stats.tiles.first { $0.key == "posts" })
        let commentsTile = try #require(stats.tiles.first { $0.key == "comments" })
        #expect(postsTile.value == "42")
        #expect(commentsTile.value == "1.3K")
    }

    // MARK: - observeSummaryStats — local counts reflected

    @Test
    func observeSummaryStats_savedTileReflectsSavedCount() async throws {
        let db = try AppDatabase.inMemory()
        let (accountId, personRowId) = try await db.writer.write { db -> (Int64, Int64) in
            let (accId, siteId) = try Self.seedAccount(db)
            let pId = try Self.seedPerson(db, siteId: siteId)
            let commId = try Self.seedCommunity(db, accountId: accId)
            _ = try Self.insertPost(db, accountId: accId, communityId: commId, personId: pId, serverPostId: 1, isSaved: true)
            _ = try Self.insertPost(db, accountId: accId, communityId: commId, personId: pId, serverPostId: 2, isSaved: true)
            return (accId, pId)
        }
        let stats = try #require(await Self.firstBatch(db.observeSummaryStats(accountId: accountId, personRowId: personRowId)))
        let savedTile = try #require(stats.tiles.first { $0.key == "saved" })
        #expect(savedTile.value == "2")
    }

    @Test
    func observeSummaryStats_readTileReflectsReadCount() async throws {
        let t = Date(timeIntervalSince1970: 2_000_000)
        let db = try AppDatabase.inMemory()
        let (accountId, personRowId) = try await db.writer.write { db -> (Int64, Int64) in
            let (accId, siteId) = try Self.seedAccount(db)
            let pId = try Self.seedPerson(db, siteId: siteId)
            try Self.insertInteraction(db, accountId: accId, postServerId: 1, lastOpenedAt: t)
            try Self.insertInteraction(db, accountId: accId, postServerId: 2, lastOpenedAt: t)
            try Self.insertInteraction(db, accountId: accId, postServerId: 3, lastOpenedAt: nil) // not opened
            return (accId, pId)
        }
        let stats = try #require(await Self.firstBatch(db.observeSummaryStats(accountId: accountId, personRowId: personRowId)))
        let readTile = try #require(stats.tiles.first { $0.key == "read" })
        #expect(readTile.value == "2")
    }
}
