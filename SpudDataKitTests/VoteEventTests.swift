//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import Testing
@testable import SpudDataKit

/// Per-test AppDatabase.inMemory() instances are isolated, so no .serialized needed.
struct VoteEventTests {
    // MARK: - Helpers

    private static func seedAccount(_ db: Database, host: String = "test.instance") throws -> Int64 {
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
        return db.lastInsertedRowID
    }

    // MARK: - Migration

    @Test
    func migrationCreatesTable() async throws {
        let db = try AppDatabase.inMemory()
        let exists = try await db.writer.read { try $0.tableExists("voteEvent") }
        #expect(exists)
    }

    @Test
    func migrationCreatesUniqueIndex() async throws {
        let db = try AppDatabase.inMemory()
        let indexes = try await db.writer.read { try $0.indexes(on: "voteEvent") }
        let hasUnique = indexes.contains { $0.name == "index_voteEvent_unique" && $0.isUnique }
        #expect(hasUnique)
    }

    @Test
    func migrationCreatesVotedAtIndex() async throws {
        let db = try AppDatabase.inMemory()
        let indexes = try await db.writer.read { try $0.indexes(on: "voteEvent") }
        let hasVotedAt = indexes.contains { $0.name == "index_voteEvent_on_votedAt" }
        #expect(hasVotedAt)
    }

    // MARK: - Round-trip

    @Test
    func roundTripInsertFetch() async throws {
        let db = try AppDatabase.inMemory()
        let accountId = try await db.writer.write { try Self.seedAccount($0) }
        let now = Date().timeIntervalSince1970

        try await db.upsertVoteEvent(
            accountId: accountId,
            entityType: "post",
            entityServerId: 42,
            voteAction: 1,
            votedAt: now,
            title: "Hello",
            body: nil,
            communityName: "swift",
            communityActorId: "https://test.instance/c/swift",
            thumbnailUrl: "https://test.instance/img.jpg",
            score: 7
        )

        let fetched = try await db.writer.read { db in
            try VoteEventRecord
                .filter(Column("accountId") == accountId)
                .fetchOne(db)
        }

        let record = try #require(fetched)
        #expect(record.entityType == "post")
        #expect(record.entityServerId == 42)
        #expect(record.voteAction == 1)
        #expect(record.votedAt == now)
        #expect(record.title == "Hello")
        #expect(record.body == nil)
        #expect(record.communityName == "swift")
        #expect(record.communityActorId == "https://test.instance/c/swift")
        #expect(record.thumbnailUrl == "https://test.instance/img.jpg")
        #expect(record.score == 7)
    }

    // MARK: - Upsert idempotency

    @Test
    func upsertIdempotency_upThenDown_updatesOneRow() async throws {
        let db = try AppDatabase.inMemory()
        let accountId = try await db.writer.write { try Self.seedAccount($0) }

        try await db.upsertVoteEvent(
            accountId: accountId, entityType: "post", entityServerId: 1,
            voteAction: 1, votedAt: 1000, title: nil, body: nil,
            communityName: nil, communityActorId: nil, thumbnailUrl: nil, score: nil
        )
        try await db.upsertVoteEvent(
            accountId: accountId, entityType: "post", entityServerId: 1,
            voteAction: 0, votedAt: 2000, title: nil, body: nil,
            communityName: nil, communityActorId: nil, thumbnailUrl: nil, score: nil
        )

        let rows = try await db.writer.read { db in
            try VoteEventRecord
                .filter(Column("accountId") == accountId)
                .filter(Column("entityType") == "post")
                .filter(Column("entityServerId") == Int64(1))
                .fetchAll(db)
        }

        #expect(rows.count == 1)
        #expect(rows[0].voteAction == 0)
        #expect(rows[0].votedAt == 2000)
    }

    @Test
    func upsertIdempotency_preservesRowId() async throws {
        let db = try AppDatabase.inMemory()
        let accountId = try await db.writer.write { try Self.seedAccount($0) }

        try await db.upsertVoteEvent(
            accountId: accountId, entityType: "comment", entityServerId: 99,
            voteAction: 1, votedAt: 1000, title: nil, body: nil,
            communityName: nil, communityActorId: nil, thumbnailUrl: nil, score: nil
        )

        let before = try await db.writer.read { db in
            try VoteEventRecord
                .filter(Column("entityServerId") == Int64(99))
                .fetchOne(db)
        }

        try await db.upsertVoteEvent(
            accountId: accountId, entityType: "comment", entityServerId: 99,
            voteAction: 0, votedAt: 2000, title: "changed", body: nil,
            communityName: nil, communityActorId: nil, thumbnailUrl: nil, score: nil
        )

        let after = try await db.writer.read { db in
            try VoteEventRecord
                .filter(Column("entityServerId") == Int64(99))
                .fetchOne(db)
        }

        #expect(before?.id == after?.id)
    }

    // MARK: - Neutral delete

    @Test
    func deleteVoteEvent_removesRow() async throws {
        let db = try AppDatabase.inMemory()
        let accountId = try await db.writer.write { try Self.seedAccount($0) }

        try await db.upsertVoteEvent(
            accountId: accountId, entityType: "post", entityServerId: 5,
            voteAction: 1, votedAt: 1000, title: nil, body: nil,
            communityName: nil, communityActorId: nil, thumbnailUrl: nil, score: nil
        )
        try await db.deleteVoteEvent(accountId: accountId, entityType: "post", entityServerId: 5)

        let count = try await db.writer.read { db in
            try VoteEventRecord
                .filter(Column("accountId") == accountId)
                .fetchCount(db)
        }
        #expect(count == 0)
    }

    @Test
    func deleteVoteEvent_noopWhenRowAbsent() async throws {
        let db = try AppDatabase.inMemory()
        let accountId = try await db.writer.write { try Self.seedAccount($0) }

        // Must not throw even when no matching row exists.
        try await db.deleteVoteEvent(accountId: accountId, entityType: "post", entityServerId: 999)
    }

    // MARK: - Account isolation

    @Test
    func accountIsolation_sameEntityServerId_twoIndependentRows() async throws {
        let db = try AppDatabase.inMemory()
        let (accountA, accountB) = try await db.writer.write { db in
            let a = try Self.seedAccount(db, host: "alpha.test")
            let b = try Self.seedAccount(db, host: "beta.test")
            return (a, b)
        }

        try await db.upsertVoteEvent(
            accountId: accountA, entityType: "post", entityServerId: 77,
            voteAction: 1, votedAt: 1000, title: "A", body: nil,
            communityName: nil, communityActorId: nil, thumbnailUrl: nil, score: nil
        )
        try await db.upsertVoteEvent(
            accountId: accountB, entityType: "post", entityServerId: 77,
            voteAction: 0, votedAt: 2000, title: "B", body: nil,
            communityName: nil, communityActorId: nil, thumbnailUrl: nil, score: nil
        )

        let rowA = try await db.writer.read { db in
            try VoteEventRecord
                .filter(Column("accountId") == accountA)
                .filter(Column("entityServerId") == Int64(77))
                .fetchOne(db)
        }
        let rowB = try await db.writer.read { db in
            try VoteEventRecord
                .filter(Column("accountId") == accountB)
                .filter(Column("entityServerId") == Int64(77))
                .fetchOne(db)
        }

        let a = try #require(rowA)
        let b = try #require(rowB)
        #expect(a.voteAction == 1)
        #expect(b.voteAction == 0)
        #expect(a.title == "A")
        #expect(b.title == "B")
    }

    // MARK: - Rollback delete

    @Test
    func rollbackDelete_removesOnlyMatchingRow() async throws {
        let db = try AppDatabase.inMemory()
        let accountId = try await db.writer.write { try Self.seedAccount($0) }

        // Insert two distinct vote events.
        try await db.upsertVoteEvent(
            accountId: accountId, entityType: "post", entityServerId: 10,
            voteAction: 1, votedAt: 1000, title: nil, body: nil,
            communityName: nil, communityActorId: nil, thumbnailUrl: nil, score: nil
        )
        try await db.upsertVoteEvent(
            accountId: accountId, entityType: "post", entityServerId: 20,
            voteAction: 1, votedAt: 2000, title: nil, body: nil,
            communityName: nil, communityActorId: nil, thumbnailUrl: nil, score: nil
        )

        // Simulate rollback: delete only the first one.
        try await db.deleteVoteEvent(accountId: accountId, entityType: "post", entityServerId: 10)

        let remaining = try await db.writer.read { db in
            try VoteEventRecord
                .filter(Column("accountId") == accountId)
                .fetchAll(db)
        }

        #expect(remaining.count == 1)
        #expect(remaining[0].entityServerId == 20)
    }
}
