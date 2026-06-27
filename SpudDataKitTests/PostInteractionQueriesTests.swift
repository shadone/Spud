//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import Testing
@testable import SpudDataKit

struct PostInteractionQueriesTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func snapshot() -> PostInteractionSnapshot {
        PostInteractionSnapshot(titleSnapshot: "Hello", communityName: "tech", instanceHost: "lemmy.world", thumbnailUrl: nil, author: "alice")
    }

    private func seedAccount(_ appDatabase: AppDatabase, keychainId: String, personServerId: Int64?) throws {
        try appDatabase.writer.write { db in
            try db.execute(sql: "INSERT INTO instance (actorId, createdAt) VALUES (?, ?)", arguments: ["https://\(keychainId).test", Date()])
            let instanceId = db.lastInsertedRowID
            try db.execute(sql: "INSERT INTO site (instanceId, createdAt, updatedAt) VALUES (?, ?, ?)", arguments: [instanceId, Date(), Date()])
            let siteId = db.lastInsertedRowID
            var personRowId: Int64?
            if let personServerId {
                try db.execute(sql: """
                    INSERT INTO person (siteId, personId, isAdmin, isBanned, isBotAccount, isDeleted, isLocal, numberOfPosts, numberOfComments, createdAt, updatedAt)
                    VALUES (?, ?, 0, 0, 0, 0, 0, 0, 0, ?, ?)
                    """, arguments: [siteId, personServerId, Date(), Date()])
                personRowId = db.lastInsertedRowID
            }
            try db.execute(sql: """
                INSERT INTO account (siteId, personId, accountKeychainId, isDefault, isServiceAccount, isSignedOutAccountType, createdAt, updatedAt)
                VALUES (?, ?, ?, 0, 0, 0, ?, ?)
                """, arguments: [siteId, personRowId, keychainId, Date(), Date()])
        }
    }

    @Test
    func lastOpenedAtSyncReturnsPriorValue() async throws {
        let appDatabase = try AppDatabase.inMemory()
        try seedAccount(appDatabase, keychainId: "kc-1", personServerId: nil)
        #expect(appDatabase.lastOpenedAtSync(forKeychainId: "kc-1", serverPostId: 9) == nil)

        try await appDatabase.recordPostOpened(accountKeychainId: "kc-1", serverPostId: 9, commentCount: nil, snapshot: snapshot(), now: t0)
        #expect(appDatabase.lastOpenedAtSync(forKeychainId: "kc-1", serverPostId: 9) == t0)
    }

    @Test
    func accountPersonServerIdSync() throws {
        let appDatabase = try AppDatabase.inMemory()
        try seedAccount(appDatabase, keychainId: "kc-1", personServerId: 555)
        try seedAccount(appDatabase, keychainId: "kc-signedout", personServerId: nil)

        #expect(appDatabase.accountPersonServerIdSync(forKeychainId: "kc-1") == 555)
        #expect(appDatabase.accountPersonServerIdSync(forKeychainId: "kc-signedout") == nil)
        #expect(appDatabase.accountPersonServerIdSync(forKeychainId: "missing") == nil)
    }
}
