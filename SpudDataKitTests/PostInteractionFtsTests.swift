//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import Testing
@testable import SpudDataKit

struct PostInteractionFtsTests {
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

    /// Inserts an interaction row directly and returns its id.
    private func insertInteraction(_ appDatabase: AppDatabase, accountId: Int64, postServerId: Int64, title: String) throws -> Int64 {
        try appDatabase.writer.write { db in
            var record = PostInteractionRecord(accountId: accountId, postServerId: postServerId)
            record.titleSnapshot = title
            record.communityName = "programming"
            record.author = "alice"
            try record.insert(db)
            return record.id!
        }
    }

    /// Helper: count FTS matches for a query, joined back to postInteraction.
    private func matchCount(_ appDatabase: AppDatabase, _ query: String) throws -> Int {
        try appDatabase.writer.read { db in
            guard let pattern = FTS5Pattern(matchingAllTokensIn: query) else { return 0 }
            return try Int.fetchOne(db, sql: """
                SELECT count(*) FROM postInteraction
                JOIN postInteractionFts ON postInteractionFts.rowid = postInteraction.id
                WHERE postInteractionFts MATCH ?
                """, arguments: [pattern]) ?? 0
        }
    }

    @Test
    func ftsTableExists() throws {
        let appDatabase = try AppDatabase.inMemory()
        let exists = try appDatabase.writer.read { db in try db.tableExists("postInteractionFts") }
        #expect(exists)
    }

    @Test
    func insertIsIndexedAndSearchable() throws {
        let appDatabase = try AppDatabase.inMemory()
        let accountId = try seedAccount(appDatabase, keychainId: "kc-1")
        _ = try insertInteraction(appDatabase, accountId: accountId, postServerId: 1, title: "Swift Concurrency explained")

        #expect(try matchCount(appDatabase, "concurrency") == 1)
        #expect(try matchCount(appDatabase, "programming") == 1) // communityName indexed
        #expect(try matchCount(appDatabase, "rust") == 0)
    }

    @Test
    func updateAndDeleteStayInSync() throws {
        let appDatabase = try AppDatabase.inMemory()
        let accountId = try seedAccount(appDatabase, keychainId: "kc-1")
        let id = try insertInteraction(appDatabase, accountId: accountId, postServerId: 1, title: "Swift Concurrency")

        // Update the indexed title; old token gone, new token present.
        try appDatabase.writer.write { db in
            try db.execute(sql: "UPDATE postInteraction SET titleSnapshot = ? WHERE id = ?", arguments: ["Rust ownership", id])
        }
        #expect(try matchCount(appDatabase, "concurrency") == 0)
        #expect(try matchCount(appDatabase, "ownership") == 1)

        // Delete; no matches remain.
        try appDatabase.writer.write { db in
            try db.execute(sql: "DELETE FROM postInteraction WHERE id = ?", arguments: [id])
        }
        #expect(try matchCount(appDatabase, "ownership") == 0)
    }
}
