//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import XCTest
@testable import SpudDataKit

final class PostInteractionWritesTests: XCTestCase {
    /// Seeds the minimal account graph (instance -> site -> account) and
    /// returns the account row id. `keychainId` lets multiple accounts coexist.
    @discardableResult
    private func seedAccount(_ appDatabase: AppDatabase, keychainId: String) throws -> Int64 {
        try appDatabase.writer.write { db in
            try db.execute(sql: "INSERT INTO instance (actorId, createdAt) VALUES (?, ?)", arguments: ["https://\(keychainId).test", Date()])
            let instanceId = db.lastInsertedRowID
            try db.execute(sql: "INSERT INTO site (instanceId, createdAt, updatedAt) VALUES (?, ?, ?)", arguments: [instanceId, Date(), Date()])
            let siteId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO account (siteId, accountKeychainId, isDefault, isServiceAccount, isSignedOutAccountType, createdAt, updatedAt)
                VALUES (?, ?, 0, 0, 0, ?, ?)
                """, arguments: [siteId, keychainId, Date(), Date()])
            return db.lastInsertedRowID
        }
    }

    private func fetchInteraction(_ appDatabase: AppDatabase, accountId: Int64, postServerId: Int64) throws -> PostInteractionRecord? {
        try appDatabase.writer.read { db in
            try PostInteractionRecord
                .filter(Column("accountId") == accountId)
                .filter(Column("postServerId") == postServerId)
                .fetchOne(db)
        }
    }

    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let t1 = Date(timeIntervalSince1970: 1_000_500)

    private func snapshot() -> PostInteractionSnapshot {
        PostInteractionSnapshot(titleSnapshot: "Hello", communityName: "tech", instanceHost: "lemmy.world", thumbnailUrl: nil, author: "alice")
    }

    func testRecordPostOpenedFirstThenSecondReturnsPrior() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let accountId = try seedAccount(appDatabase, keychainId: "kc-1")

        let first = try await appDatabase.recordPostOpened(
            accountKeychainId: "kc-1", serverPostId: 9, commentCount: 12, snapshot: snapshot(), now: t0
        )
        XCTAssertNil(first)

        let second = try await appDatabase.recordPostOpened(
            accountKeychainId: "kc-1", serverPostId: 9, commentCount: 15, snapshot: nil, now: t1
        )
        XCTAssertEqual(second, t0)

        let record = try XCTUnwrap(fetchInteraction(appDatabase, accountId: accountId, postServerId: 9))
        XCTAssertEqual(record.openedCount, 2)
        XCTAssertEqual(record.lastOpenedAt, t1)
        XCTAssertEqual(record.lastKnownCommentCount, 15)
        XCTAssertEqual(record.titleSnapshot, "Hello")
    }

    func testRecordPostOpenedUnknownAccountNoOps() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let result = try await appDatabase.recordPostOpened(
            accountKeychainId: "missing", serverPostId: 9, commentCount: nil, snapshot: nil, now: t0
        )
        XCTAssertNil(result)
    }

    func testRecordPostSeenAccumulates() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let accountId = try seedAccount(appDatabase, keychainId: "kc-1")

        try await appDatabase.recordPostSeen(accountKeychainId: "kc-1", serverPostId: 9, snapshot: snapshot(), now: t0)
        try await appDatabase.recordPostSeen(accountKeychainId: "kc-1", serverPostId: 9, snapshot: snapshot(), now: t1)

        let record = try XCTUnwrap(fetchInteraction(appDatabase, accountId: accountId, postServerId: 9))
        XCTAssertEqual(record.seenCount, 2)
        XCTAssertEqual(record.firstSeenAt, t0)
        XCTAssertEqual(record.lastSeenAt, t1)
    }

    func testPruneDeletesOldSeenKeepsRecentAndOpened() async throws {
        let appDatabase = try AppDatabase.inMemory()
        try seedAccount(appDatabase, keychainId: "kc-1")

        // Old seen-only (40 days ago) -> pruned.
        try await appDatabase.recordPostSeen(accountKeychainId: "kc-1", serverPostId: 1, snapshot: snapshot(), now: t0)
        // Recent seen-only (now) -> kept.
        let now = t0.addingTimeInterval(40 * 86400)
        try await appDatabase.recordPostSeen(accountKeychainId: "kc-1", serverPostId: 2, snapshot: snapshot(), now: now)
        // Opened 40 days ago -> kept (opened retention is 1 year).
        try await appDatabase.recordPostOpened(accountKeychainId: "kc-1", serverPostId: 3, commentCount: nil, snapshot: snapshot(), now: t0)

        let deleted = try await appDatabase.prunePostInteractions(now: now)
        XCTAssertEqual(deleted, 1)

        let accountId = try await appDatabase.writer.read { db in try Int64.fetchOne(db, sql: "SELECT id FROM account LIMIT 1")! }
        XCTAssertNil(try fetchInteraction(appDatabase, accountId: accountId, postServerId: 1))
        XCTAssertNotNil(try fetchInteraction(appDatabase, accountId: accountId, postServerId: 2))
        XCTAssertNotNil(try fetchInteraction(appDatabase, accountId: accountId, postServerId: 3))
    }
}
