//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import Testing
@testable import SpudDataKit

struct OutboundContentMigrationTests {
    @Test
    func tableExistsAfterMigration() async throws {
        let db = try AppDatabase.inMemory()
        let exists = try await db.writer.read { try $0.tableExists("outboundContent") }
        #expect(exists)
    }

    @Test
    func partialUniqueIndexAllowsManyNonDrafts_butOneDraftPerTarget() async throws {
        let db = try AppDatabase.inMemory()
        // Seed an account row (FK target). Minimal insert via raw SQL is brittle across schema;
        // instead use accountId that satisfies the FK by inserting through the account table.
        let accountId = try await Self.seedAccount(db)
        try await db.writer.write { write in
            func row(status: Int64, token: String) -> OutboundContentRecord {
                OutboundContentRecord(
                    id: nil, clientToken: token, accountId: accountId, kind: 0, status: status,
                    draftKey: "c:1:0", body: "x", postServerId: 1, parentCommentServerId: nil,
                    communityServerId: nil, title: nil, url: nil, nsfw: false, postType: 0,
                    attempts: 0, lastError: nil, nextAttemptAt: nil, createdAt: 0, updatedAt: 0
                )
            }
            var d1 = row(status: 0, token: "a")
            try d1.insert(write)
            // Two queued (status=1) rows to the same target are allowed.
            var q1 = row(status: 1, token: "b")
            try q1.insert(write)
            var q2 = row(status: 1, token: "c")
            try q2.insert(write)
        }
        // A second draft (status=0) to the same target must violate the partial unique index.
        await #expect(throws: (any Error).self) {
            try await db.writer.write { write in
                var d2 = OutboundContentRecord(
                    id: nil, clientToken: "d", accountId: accountId, kind: 0, status: 0,
                    draftKey: "c:1:0", body: "y", postServerId: 1, parentCommentServerId: nil,
                    communityServerId: nil, title: nil, url: nil, nsfw: false, postType: 0,
                    attempts: 0, lastError: nil, nextAttemptAt: nil, createdAt: 0, updatedAt: 0
                )
                try d2.insert(write)
            }
        }
    }

    /// Inserts a minimal account row and returns its id. Mirrors how other
    /// SpudDataKitTests seed FK parents (see PostInteractionMigrationTests).
    static func seedAccount(_ db: AppDatabase) async throws -> Int64 {
        try await db.writer.write { write in
            try write.execute(sql: "INSERT INTO instance (actorId, createdAt) VALUES ('https://seed.test', ?)", arguments: [Date()])
            let instanceId = write.lastInsertedRowID
            try write.execute(sql: "INSERT INTO site (instanceId, createdAt, updatedAt) VALUES (?, ?, ?)", arguments: [instanceId, Date(), Date()])
            let siteId = write.lastInsertedRowID
            try write.execute(sql: """
                INSERT INTO account (siteId, accountKeychainId, isDefault, isServiceAccount, isSignedOutAccountType, createdAt, updatedAt)
                VALUES (?, 'test@example.com', 0, 0, 0, ?, ?)
                """, arguments: [siteId, Date(), Date()])
            return write.lastInsertedRowID
        }
    }
}
