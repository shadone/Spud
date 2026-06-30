//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import Testing
@testable import SpudDataKit

/// Per-test AppDatabase.inMemory() instances are isolated — no .serialized needed.
struct ActivityObservationsTests {
    // MARK: - Helpers

    private static func seedGraph(_ db: Database, host: String = "test.instance") throws -> (accountId: Int64, communityId: Int64, personId: Int64) {
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
                INSERT INTO person (siteId, personId, name, isAdmin, isBanned, isBotAccount, isDeleted, isLocal,
                                    numberOfPosts, numberOfComments, createdAt, updatedAt)
                VALUES (?, 10, 'alice', 0, 0, 0, 0, 0, 0, 0, ?, ?)
                """,
            arguments: [siteId, Date(), Date()]
        )
        let personId = db.lastInsertedRowID
        try db.execute(
            sql: """
                INSERT INTO account (siteId, accountKeychainId, isDefault, isServiceAccount,
                                     isSignedOutAccountType, createdAt, updatedAt)
                VALUES (?, ?, 0, 0, 0, ?, ?)
                """,
            arguments: [siteId, "kc-\(host)", Date(), Date()]
        )
        let accountId = db.lastInsertedRowID
        try db.execute(
            sql: """
                INSERT INTO community (accountId, communityId, name, actorId, isHidden, isLocal, isNsfw,
                                       isPostingRestrictedToMods, isRemoved, subscribedState,
                                       numberOfSubscribers, numberOfPosts, numberOfComments, createdAt, updatedAt)
                VALUES (?, 5, 'test', 'https://\(host)/c/test', 0, 0, 0, 0, 0, 'NotSubscribed', 0, 0, 0, ?, ?)
                """,
            arguments: [accountId, Date(), Date()]
        )
        let communityId = db.lastInsertedRowID
        return (accountId, communityId, personId)
    }

    private static func insertPost(
        _ db: Database,
        accountId: Int64,
        communityId: Int64,
        personId: Int64,
        serverPostId: Int64,
        title: String,
        isSaved: Bool = false,
        isHidden: Bool = false,
        published: Date = Date()
    ) throws -> Int64 {
        try db.execute(
            sql: """
                INSERT INTO post (accountId, communityId, creatorId, postId, title, originalPostUrl,
                                  score, numberOfUpvotes, numberOfDownvotes, numberOfComments,
                                  isRead, isSaved, isHidden, isRemoved, isLocked,
                                  isFeaturedCommunity, isFeaturedLocal, isDeleted, published, createdAt, updatedAt)
                VALUES (?, ?, ?, ?, ?, 'https://\(serverPostId).test',
                        7, 7, 0, 3, 0, ?, ?, 0, 0, 0, 0, 0, ?, ?, ?)
                """,
            arguments: [
                accountId,
                communityId,
                personId,
                serverPostId,
                title,
                isSaved,
                isHidden,
                published,
                Date(),
                Date(),
            ]
        )
        return db.lastInsertedRowID
    }

    private static func insertComment(
        _ db: Database,
        postRowId: Int64,
        personId: Int64,
        localCommentId: Int64,
        body: String,
        isSaved: Bool = false,
        published: Date = Date()
    ) throws -> Int64 {
        try db.execute(
            sql: """
                INSERT INTO comment (postId, creatorId, localCommentId, body, score,
                                     numberOfUpvotes, numberOfDownvotes, isSaved, isRemoved,
                                     isDistinguished, isDeleted, isCreatorModerator, isCreatorAdmin,
                                     isCreatorBannedFromCommunity, isCreatorBlocked,
                                     originalCommentUrl, published, createdAt, updatedAt)
                VALUES (?, ?, ?, ?, 0, 0, 0, ?, 0, 0, 0, 0, 0, 0, 0,
                        'https://\(localCommentId).test/comment', ?, ?, ?)
                """,
            arguments: [postRowId, personId, localCommentId, body, isSaved, published, Date(), Date()]
        )
        return db.lastInsertedRowID
    }

    private static func insertInteraction(
        _ db: Database,
        accountId: Int64,
        postServerId: Int64,
        title: String,
        lastOpenedAt: Date?,
        lastSeenAt: Date?
    ) throws {
        var record = PostInteractionRecord(accountId: accountId, postServerId: postServerId)
        record.titleSnapshot = title
        record.lastOpenedAt = lastOpenedAt
        record.lastSeenAt = lastSeenAt
        try record.insert(db)
    }

    private static func insertVoteEvent(
        _ db: AppDatabase,
        accountId: Int64,
        entityType: String,
        entityServerId: Int64,
        voteAction: Int64,
        votedAt: Double,
        title: String? = nil,
        body: String? = nil,
        communityName: String? = nil,
        communityActorId: String? = nil,
        score: Int64? = nil
    ) async throws {
        try await db.upsertVoteEvent(
            accountId: accountId,
            entityType: entityType,
            entityServerId: entityServerId,
            voteAction: voteAction,
            votedAt: votedAt,
            title: title,
            body: body,
            communityName: communityName,
            communityActorId: communityActorId,
            thumbnailUrl: nil,
            score: score
        )
    }

    private static func firstBatch(_ stream: AsyncStream<[ActivityItem]>) async -> [ActivityItem] {
        for await items in stream {
            return items
        }
        return []
    }

    // MARK: - Read source

    @Test
    func readSource_returnsOpenedPosts_withReadAct() async throws {
        let t1 = Date(timeIntervalSince1970: 1_000_100)
        let t2 = Date(timeIntervalSince1970: 1_000_200)
        let db = try AppDatabase.inMemory()
        let accountId = try await db.writer.write { db -> Int64 in
            let g = try Self.seedGraph(db)
            _ = try Self.insertPost(db, accountId: g.accountId, communityId: g.communityId, personId: g.personId, serverPostId: 1, title: "Post 1")
            _ = try Self.insertPost(db, accountId: g.accountId, communityId: g.communityId, personId: g.personId, serverPostId: 2, title: "Post 2")
            _ = try Self.insertPost(db, accountId: g.accountId, communityId: g.communityId, personId: g.personId, serverPostId: 3, title: "Not opened")
            try Self.insertInteraction(db, accountId: g.accountId, postServerId: 1, title: "Post 1", lastOpenedAt: t1, lastSeenAt: nil)
            try Self.insertInteraction(db, accountId: g.accountId, postServerId: 2, title: "Post 2", lastOpenedAt: t2, lastSeenAt: nil)
            try Self.insertInteraction(db, accountId: g.accountId, postServerId: 3, title: "Not opened", lastOpenedAt: nil, lastSeenAt: t1)
            return g.accountId
        }
        let items = await Self.firstBatch(db.observeLocalActivity(accountId: accountId, filters: [.read], searchQuery: nil))
        #expect(items.allSatisfy { $0.act == .read })
        let postIds = items.compactMap { if case let .post(r) = $0.object { return r.serverPostId } else { return nil } }
        // Only the two opened posts; seen post excluded
        #expect(Set(postIds) == Set([1, 2]))
        // Newest opened first (t2 > t1)
        #expect(postIds.first == 2)
    }

    // MARK: - Seen source

    @Test
    func seenSource_returnsSeenNotOpened_withSeenAct() async throws {
        let t1 = Date(timeIntervalSince1970: 1_000_100)
        let t2 = Date(timeIntervalSince1970: 1_000_200)
        let db = try AppDatabase.inMemory()
        let accountId = try await db.writer.write { db -> Int64 in
            let g = try Self.seedGraph(db)
            _ = try Self.insertPost(db, accountId: g.accountId, communityId: g.communityId, personId: g.personId, serverPostId: 1, title: "Opened post")
            _ = try Self.insertPost(db, accountId: g.accountId, communityId: g.communityId, personId: g.personId, serverPostId: 2, title: "Seen only")
            try Self.insertInteraction(db, accountId: g.accountId, postServerId: 1, title: "Opened post", lastOpenedAt: t1, lastSeenAt: t1)
            try Self.insertInteraction(db, accountId: g.accountId, postServerId: 2, title: "Seen only", lastOpenedAt: nil, lastSeenAt: t2)
            return g.accountId
        }
        let items = await Self.firstBatch(db.observeLocalActivity(accountId: accountId, filters: [.seen], searchQuery: nil))
        #expect(items.allSatisfy { $0.act == .seen })
        // Only the seen-only post; opened post excluded (mutual exclusion)
        let ids = items.compactMap { if case let .post(r) = $0.object { return r.serverPostId } else { return nil } }
        #expect(ids == [2])
    }

    // MARK: - Read vs Seen mutual exclusion

    @Test
    func readAndSeenMutuallyExclusive_combinedFilters() async throws {
        let tSeen = Date(timeIntervalSince1970: 1_000_100)
        let tOpened = Date(timeIntervalSince1970: 1_000_200)
        let db = try AppDatabase.inMemory()
        let accountId = try await db.writer.write { db -> Int64 in
            let g = try Self.seedGraph(db)
            // Post that was both seen AND opened — should appear under .read, not .seen
            _ = try Self.insertPost(db, accountId: g.accountId, communityId: g.communityId, personId: g.personId, serverPostId: 1, title: "Both")
            _ = try Self.insertPost(db, accountId: g.accountId, communityId: g.communityId, personId: g.personId, serverPostId: 2, title: "Seen only")
            try Self.insertInteraction(db, accountId: g.accountId, postServerId: 1, title: "Both", lastOpenedAt: tOpened, lastSeenAt: tSeen)
            try Self.insertInteraction(db, accountId: g.accountId, postServerId: 2, title: "Seen only", lastOpenedAt: nil, lastSeenAt: tSeen)
            return g.accountId
        }
        let items = await Self.firstBatch(db.observeLocalActivity(accountId: accountId, filters: [.read, .seen], searchQuery: nil))
        let readItems = items.filter { $0.act == .read }
        let seenItems = items.filter { $0.act == .seen }
        let readPostIds = readItems.compactMap { if case let .post(r) = $0.object { return r.serverPostId } else { return nil } }
        let seenPostIds = seenItems.compactMap { if case let .post(r) = $0.object { return r.serverPostId } else { return nil } }
        // Post 1 (both seen + opened) must appear only as .read
        #expect(readPostIds.contains(1))
        #expect(!seenPostIds.contains(1))
        // Post 2 (seen-only) appears as .seen
        #expect(seenPostIds.contains(2))
        // No duplication: total = 2 items
        #expect(items.count == 2)
    }

    // MARK: - Save post

    @Test
    func savePost_returnsSavedPosts_withSaveAct() async throws {
        let db = try AppDatabase.inMemory()
        let accountId = try await db.writer.write { db -> Int64 in
            let g = try Self.seedGraph(db)
            _ = try Self.insertPost(db, accountId: g.accountId, communityId: g.communityId, personId: g.personId, serverPostId: 10, title: "Saved", isSaved: true)
            _ = try Self.insertPost(db, accountId: g.accountId, communityId: g.communityId, personId: g.personId, serverPostId: 11, title: "Not saved", isSaved: false)
            return g.accountId
        }
        let items = await Self.firstBatch(db.observeLocalActivity(accountId: accountId, filters: [.save], searchQuery: nil))
        let postItems = items.filter { if case .post = $0.object { return true } else { return false } }
        #expect(postItems.count == 1)
        #expect(postItems[0].act == .save)
        if case let .post(r) = postItems[0].object {
            #expect(r.serverPostId == 10)
        }
    }

    // MARK: - Save comment

    @Test
    func saveComment_returnsSavedComments_withSaveAct() async throws {
        let pub = Date(timeIntervalSince1970: 2_000_000)
        let db = try AppDatabase.inMemory()
        let accountId = try await db.writer.write { db -> Int64 in
            let g = try Self.seedGraph(db)
            let postRowId = try Self.insertPost(db, accountId: g.accountId, communityId: g.communityId, personId: g.personId, serverPostId: 20, title: "Parent post")
            _ = try Self.insertComment(db, postRowId: postRowId, personId: g.personId, localCommentId: 101, body: "Saved comment", isSaved: true, published: pub)
            _ = try Self.insertComment(db, postRowId: postRowId, personId: g.personId, localCommentId: 102, body: "Unsaved comment", isSaved: false, published: pub)
            return g.accountId
        }
        let items = await Self.firstBatch(db.observeLocalActivity(accountId: accountId, filters: [.save], searchQuery: nil))
        let commentItems = items.filter { if case .comment = $0.object { return true } else { return false } }
        #expect(commentItems.count == 1)
        #expect(commentItems[0].act == .save)
        if case let .comment(c) = commentItems[0].object {
            #expect(c.serverCommentId == 101)
            #expect(c.body == "Saved comment")
            #expect(c.parentPostTitle == "Parent post")
            #expect(c.published == pub)
        }
    }

    // MARK: - Hide

    @Test
    func hideSource_returnsHiddenPosts_withHideAct() async throws {
        let db = try AppDatabase.inMemory()
        let accountId = try await db.writer.write { db -> Int64 in
            let g = try Self.seedGraph(db)
            _ = try Self.insertPost(db, accountId: g.accountId, communityId: g.communityId, personId: g.personId, serverPostId: 30, title: "Hidden", isHidden: true)
            _ = try Self.insertPost(db, accountId: g.accountId, communityId: g.communityId, personId: g.personId, serverPostId: 31, title: "Visible", isHidden: false)
            return g.accountId
        }
        let items = await Self.firstBatch(db.observeLocalActivity(accountId: accountId, filters: [.hide], searchQuery: nil))
        #expect(items.count == 1)
        #expect(items[0].act == .hide)
        if case let .post(r) = items[0].object {
            #expect(r.serverPostId == 30)
        }
    }

    // MARK: - Upvote / downvote

    @Test
    func voteSource_upvoteMapsToUpvoteAct() async throws {
        let votedAt = Date(timeIntervalSince1970: 3_000_000)
        let db = try AppDatabase.inMemory()
        let accountId = try await db.writer.write { try Self.seedGraph($0).accountId }
        try await Self.insertVoteEvent(
            db,
            accountId: accountId,
            entityType: "post",
            entityServerId: 40,
            voteAction: 1,
            votedAt: votedAt.timeIntervalSince1970,
            title: "Upvoted post",
            communityName: "test"
        )
        let items = await Self.firstBatch(db.observeLocalActivity(accountId: accountId, filters: [.vote], searchQuery: nil))
        #expect(items.count == 1)
        #expect(items[0].act == .upvote)
        #expect(abs(items[0].occurredAt.timeIntervalSince1970 - votedAt.timeIntervalSince1970) < 0.001)
    }

    @Test
    func voteSource_downvoteMapsToDownvoteAct() async throws {
        let db = try AppDatabase.inMemory()
        let accountId = try await db.writer.write { try Self.seedGraph($0).accountId }
        try await Self.insertVoteEvent(
            db,
            accountId: accountId,
            entityType: "post",
            entityServerId: 41,
            voteAction: 0,
            votedAt: 3_000_001,
            title: "Downvoted post",
            communityName: "test"
        )
        let items = await Self.firstBatch(db.observeLocalActivity(accountId: accountId, filters: [.vote], searchQuery: nil))
        #expect(items.count == 1)
        #expect(items[0].act == .downvote)
    }

    // MARK: - Snapshot fallback (no live post row)

    @Test
    func votePost_snapshotFallback_postRowIdIsZero() async throws {
        let db = try AppDatabase.inMemory()
        let accountId = try await db.writer.write { try Self.seedGraph($0).accountId }
        // Vote on a post that was never imported into the `post` table
        try await Self.insertVoteEvent(
            db,
            accountId: accountId,
            entityType: "post",
            entityServerId: 999,
            voteAction: 1,
            votedAt: 4_000_000,
            title: "Snapshot-only title",
            communityName: "snapcommunity",
            communityActorId: "https://test.instance/c/snapcommunity",
            score: 5
        )
        let items = await Self.firstBatch(db.observeLocalActivity(accountId: accountId, filters: [.vote], searchQuery: nil))
        #expect(items.count == 1)
        if case let .post(r) = items[0].object {
            // id == 0 signals snapshot-only (no live row)
            #expect(r.id == 0)
            #expect(r.serverPostId == 999)
            #expect(r.title == "Snapshot-only title")
            #expect(r.communityName == "snapcommunity")
        } else {
            Issue.record("Expected .post object for snapshot-only voteEvent")
        }
    }

    @Test
    func voteComment_snapshotFallback_commentRowIdIsZero() async throws {
        let db = try AppDatabase.inMemory()
        let accountId = try await db.writer.write { try Self.seedGraph($0).accountId }
        // Vote on a comment that was never imported into the `comment` table
        try await Self.insertVoteEvent(
            db,
            accountId: accountId,
            entityType: "comment",
            entityServerId: 888,
            voteAction: 1,
            votedAt: 4_000_001,
            title: "Parent post title",
            body: "Snapshot comment body",
            communityName: "test"
        )
        let items = await Self.firstBatch(db.observeLocalActivity(accountId: accountId, filters: [.vote], searchQuery: nil))
        #expect(items.count == 1)
        if case let .comment(c) = items[0].object {
            #expect(c.id == 0)
            #expect(c.serverCommentId == 888)
            #expect(c.body == "Snapshot comment body")
            #expect(c.serverPostId == nil)
        } else {
            Issue.record("Expected .comment object for snapshot-only voteEvent")
        }
    }

    // MARK: - Combined sort (occurredAt desc)

    @Test
    func combinedSort_mixedSources_descendingByOccurredAt() async throws {
        let t1 = Date(timeIntervalSince1970: 1_000_000)
        let t2 = Date(timeIntervalSince1970: 2_000_000)
        let t3 = Date(timeIntervalSince1970: 3_000_000)
        let db = try AppDatabase.inMemory()
        let accountId = try await db.writer.write { db -> Int64 in
            let g = try Self.seedGraph(db)
            // Read post at t1
            _ = try Self.insertPost(db, accountId: g.accountId, communityId: g.communityId, personId: g.personId, serverPostId: 50, title: "Read", published: t1)
            try Self.insertInteraction(db, accountId: g.accountId, postServerId: 50, title: "Read", lastOpenedAt: t1, lastSeenAt: nil)
            // Saved comment at t2 (published)
            let p2id = try Self.insertPost(db, accountId: g.accountId, communityId: g.communityId, personId: g.personId, serverPostId: 51, title: "Parent", published: t2)
            _ = try Self.insertComment(db, postRowId: p2id, personId: g.personId, localCommentId: 200, body: "Saved comment", isSaved: true, published: t2)
            return g.accountId
        }
        // Vote on post at t3 (after write block to avoid nesting async in sync)
        try await Self.insertVoteEvent(
            db,
            accountId: accountId,
            entityType: "post",
            entityServerId: 52,
            voteAction: 1,
            votedAt: t3.timeIntervalSince1970,
            title: "Voted post",
            communityName: "test"
        )
        let items = await Self.firstBatch(db.observeLocalActivity(accountId: accountId, filters: [.read, .save, .vote], searchQuery: nil))
        // Expect descending: t3 (vote) > t2 (save comment) > t1 (read)
        #expect(items.count == 3)
        #expect(items[0].occurredAt >= items[1].occurredAt)
        #expect(items[1].occurredAt >= items[2].occurredAt)
        #expect(items[0].act == .upvote)
        #expect(items[2].act == .read)
    }

    // MARK: - Account isolation

    @Test
    func accountIsolation_doesNotLeakAcrossAccounts() async throws {
        let t1 = Date(timeIntervalSince1970: 1_000_100)
        let db = try AppDatabase.inMemory()
        let (accA, accB) = try await db.writer.write { db -> (Int64, Int64) in
            let gA = try Self.seedGraph(db, host: "alpha.test")
            let gB = try Self.seedGraph(db, host: "beta.test")
            _ = try Self.insertPost(db, accountId: gA.accountId, communityId: gA.communityId, personId: gA.personId, serverPostId: 1, title: "Alpha post")
            _ = try Self.insertPost(db, accountId: gB.accountId, communityId: gB.communityId, personId: gB.personId, serverPostId: 2, title: "Beta post")
            try Self.insertInteraction(db, accountId: gA.accountId, postServerId: 1, title: "Alpha post", lastOpenedAt: t1, lastSeenAt: nil)
            try Self.insertInteraction(db, accountId: gB.accountId, postServerId: 2, title: "Beta post", lastOpenedAt: t1, lastSeenAt: nil)
            return (gA.accountId, gB.accountId)
        }
        let itemsA = await Self.firstBatch(db.observeLocalActivity(accountId: accA, filters: [.read], searchQuery: nil))
        let itemsB = await Self.firstBatch(db.observeLocalActivity(accountId: accB, filters: [.read], searchQuery: nil))
        #expect(itemsA.count == 1)
        #expect(itemsB.count == 1)
        if case let .post(r) = itemsA[0].object { #expect(r.serverPostId == 1) }
        if case let .post(r) = itemsB[0].object { #expect(r.serverPostId == 2) }
    }

    // MARK: - Filter exclusion

    @Test
    func filterExclusion_onlyRequestedFiltersReturn() async throws {
        let t1 = Date(timeIntervalSince1970: 1_000_100)
        let db = try AppDatabase.inMemory()
        let accountId = try await db.writer.write { db -> Int64 in
            let g = try Self.seedGraph(db)
            _ = try Self.insertPost(db, accountId: g.accountId, communityId: g.communityId, personId: g.personId, serverPostId: 60, title: "Read post")
            _ = try Self.insertPost(db, accountId: g.accountId, communityId: g.communityId, personId: g.personId, serverPostId: 61, title: "Saved post", isSaved: true)
            try Self.insertInteraction(db, accountId: g.accountId, postServerId: 60, title: "Read post", lastOpenedAt: t1, lastSeenAt: nil)
            return g.accountId
        }
        // Request only .save — the .read post must not appear
        let items = await Self.firstBatch(db.observeLocalActivity(accountId: accountId, filters: [.save], searchQuery: nil))
        #expect(items.count == 1)
        #expect(items[0].act == .save)
        if case let .post(r) = items[0].object { #expect(r.serverPostId == 61) }
    }

    // MARK: - Stable IDs

    @Test
    func stableIds_uniquePerSourceAndObject() async throws {
        let t1 = Date(timeIntervalSince1970: 1_000_100)
        let db = try AppDatabase.inMemory()
        let accountId = try await db.writer.write { db -> Int64 in
            let g = try Self.seedGraph(db)
            _ = try Self.insertPost(db, accountId: g.accountId, communityId: g.communityId, personId: g.personId, serverPostId: 70, title: "Multi-source", isSaved: true)
            try Self.insertInteraction(db, accountId: g.accountId, postServerId: 70, title: "Multi-source", lastOpenedAt: t1, lastSeenAt: nil)
            return g.accountId
        }
        let items = await Self.firstBatch(db.observeLocalActivity(accountId: accountId, filters: [.read, .save], searchQuery: nil))
        // Same post appears as both "read-post-70" and "save-post-70" — distinct IDs
        let ids = items.map(\.id)
        #expect(ids.count == Set(ids).count) // all IDs unique
        #expect(ids.contains("read-post-70"))
        #expect(ids.contains("save-post-70"))
    }
}
