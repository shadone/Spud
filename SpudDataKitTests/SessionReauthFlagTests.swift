//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import Testing
@testable import SpudDataKit

struct SessionReauthFlagTests {
    /// Inserts a real signed-in account row and returns its keychain id + rowid.
    private func makeSignedInAccount(_ db: AppDatabase) async throws -> (keychainId: String, accountId: Int64) {
        let keychainId = "kc-signed-in"
        let accountId: Int64 = try await db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO instance (actorId, createdAt, updatedAt)
                VALUES ('https://lemmy.example', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
                """)
            let instanceId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO site (instanceId, createdAt, updatedAt)
                VALUES (?, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
                """, arguments: [instanceId])
            let siteId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO account
                    (siteId, accountKeychainId, isDefault, isServiceAccount,
                     isSignedOutAccountType, isEphemeral, createdAt, updatedAt)
                VALUES (?, ?, 1, 0, 0, 0, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
                """, arguments: [siteId, keychainId])
            return db.lastInsertedRowID
        }
        return (keychainId, accountId)
    }

    @Test
    func migrationAddsFlagDefaultingFalse() async throws {
        let db = try AppDatabase.inMemory()
        let (keychainId, _) = try await makeSignedInAccount(db)
        let record = db.accountRecordSync(forKeychainId: keychainId)
        #expect(record?.sessionNeedsReauth == false)
    }

    @Test
    func setAndClearByKeychainId() async throws {
        let db = try AppDatabase.inMemory()
        let (keychainId, _) = try await makeSignedInAccount(db)

        try await db.setAccountSessionNeedsReauth(keychainId: keychainId, true)
        #expect(db.accountRecordSync(forKeychainId: keychainId)?.sessionNeedsReauth == true)
        #expect(db.accountAnyNeedsReauthSync())

        try await db.setAccountSessionNeedsReauth(keychainId: keychainId, false)
        #expect(db.accountRecordSync(forKeychainId: keychainId)?.sessionNeedsReauth == false)
        #expect(!db.accountAnyNeedsReauthSync())
    }

    @Test
    func setByAccountIdMatchesKeychainId() async throws {
        let db = try AppDatabase.inMemory()
        let (keychainId, accountId) = try await makeSignedInAccount(db)
        try await db.setAccountSessionNeedsReauth(accountId: accountId, true)
        #expect(db.accountRecordSync(forKeychainId: keychainId)?.sessionNeedsReauth == true)
    }

    @Test
    func signedOutAccountNeverFlaggable() async throws {
        let db = try AppDatabase.inMemory()
        let keychainId = "kc-signed-out"
        try await db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO instance (actorId, createdAt, updatedAt)
                VALUES ('https://lemmy.example', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
                """)
            let instanceId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO site (instanceId, createdAt, updatedAt)
                VALUES (?, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
                """, arguments: [instanceId])
            let siteId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO account
                    (siteId, accountKeychainId, isDefault, isServiceAccount,
                     isSignedOutAccountType, isEphemeral, createdAt, updatedAt)
                VALUES (?, ?, 1, 0, 1, 0, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
                """, arguments: [siteId, keychainId])
        }
        // The WHERE guard makes this a no-op, not an error.
        try await db.setAccountSessionNeedsReauth(keychainId: keychainId, true)
        #expect(db.accountRecordSync(forKeychainId: keychainId)?.sessionNeedsReauth == false)
        #expect(!db.accountAnyNeedsReauthSync())
    }

    @Test
    func accountListRowCarriesFlag() async throws {
        let db = try AppDatabase.inMemory()
        let (keychainId, _) = try await makeSignedInAccount(db)
        try await db.setAccountSessionNeedsReauth(keychainId: keychainId, true)

        var iterator = db.observeAccountListRows().makeAsyncIterator()
        let rows = await iterator.next()
        let row = rows?.first { $0.accountKeychainId == keychainId }
        #expect(row?.sessionNeedsReauth == true)
    }
}
