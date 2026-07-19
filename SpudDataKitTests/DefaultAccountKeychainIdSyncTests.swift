//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import Testing
@testable import SpudDataKit

/// `defaultAccountKeychainIdSync()` shares its selection logic with
/// `observeDefaultAccount()` (both filter `isDefault == true` and
/// `isServiceAccount == false`) so the two can never disagree on which
/// account counts as default.
struct DefaultAccountKeychainIdSyncTests {
    private static func seedAccount(
        _ db: Database, keychainId: String, host: String, isDefault: Bool, isServiceAccount: Bool
    ) throws {
        try db.execute(sql: "INSERT INTO instance (actorId, createdAt) VALUES (?, ?)", arguments: ["https://\(host)", Date()])
        let instanceId = db.lastInsertedRowID
        try db.execute(sql: "INSERT INTO site (instanceId, createdAt, updatedAt) VALUES (?, ?, ?)", arguments: [instanceId, Date(), Date()])
        let siteId = db.lastInsertedRowID
        try db.execute(sql: """
            INSERT INTO account (siteId, accountKeychainId, isDefault, isServiceAccount, isSignedOutAccountType, createdAt, updatedAt)
            VALUES (?, ?, ?, ?, 0, ?, ?)
            """, arguments: [siteId, keychainId, isDefault, isServiceAccount, Date(), Date()])
    }

    @Test
    func defaultAccountKeychainIdSync_serviceAndDefaultSeeded_returnsDefaultsKeychainId() async throws {
        let appDatabase = try AppDatabase.inMemory()
        try await appDatabase.writer.write { db in
            // A service account is internal bookkeeping and must never be
            // mistaken for the default even though it may be inserted first.
            try Self.seedAccount(db, keychainId: "kc-service", host: "service.test", isDefault: false, isServiceAccount: true)
            try Self.seedAccount(db, keychainId: "kc-default", host: "lemmy.world", isDefault: true, isServiceAccount: false)
        }
        #expect(appDatabase.defaultAccountKeychainIdSync() == "kc-default")
    }

    @Test
    func defaultAccountKeychainIdSync_emptyDatabase_returnsNil() throws {
        let appDatabase = try AppDatabase.inMemory()
        #expect(appDatabase.defaultAccountKeychainIdSync() == nil)
    }

    @Test
    func defaultAccountKeychainIdSync_serviceAccountMarkedDefault_isExcluded() async throws {
        // isDefault is never actually set on a service account in production,
        // but the query's isServiceAccount filter must hold even if it were —
        // mirrors observeDefaultAccount()'s same double filter.
        let appDatabase = try AppDatabase.inMemory()
        try await appDatabase.writer.write { db in
            try Self.seedAccount(db, keychainId: "kc-service", host: "service.test", isDefault: true, isServiceAccount: true)
        }
        #expect(appDatabase.defaultAccountKeychainIdSync() == nil)
    }
}
