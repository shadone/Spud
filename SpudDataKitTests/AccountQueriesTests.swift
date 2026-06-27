//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import Testing
@testable import SpudDataKit

struct AccountQueriesTests {
    private static func seedAccount(_ db: Database, keychainId: String, host: String, isDefault: Bool, signedOut: Bool) throws {
        try db.execute(sql: "INSERT INTO instance (actorId, createdAt) VALUES (?, ?)", arguments: ["https://\(host)", Date()])
        let instanceId = db.lastInsertedRowID
        try db.execute(sql: "INSERT INTO site (instanceId, createdAt, updatedAt) VALUES (?, ?, ?)", arguments: [instanceId, Date(), Date()])
        let siteId = db.lastInsertedRowID
        try db.execute(sql: """
            INSERT INTO account (siteId, accountKeychainId, isDefault, isServiceAccount, isSignedOutAccountType, createdAt, updatedAt)
            VALUES (?, ?, ?, 0, ?, ?, ?)
            """, arguments: [siteId, keychainId, isDefault, signedOut, Date(), Date()])
    }

    @Test
    func accountsSync_returnsNonServiceAccountsWithHosts() async throws {
        let appDatabase = try AppDatabase.inMemory()
        try await appDatabase.writer.write { db in
            try Self.seedAccount(db, keychainId: "kc-1", host: "lemmy.world", isDefault: true, signedOut: false)
            try Self.seedAccount(db, keychainId: "kc-2", host: "beehaw.org", isDefault: false, signedOut: true)
        }
        let rows = appDatabase.accountsSync()
        #expect(Set(rows.map(\.accountKeychainId)) == ["kc-1", "kc-2"])
        #expect(Set(rows.map(\.instanceHostname)) == ["lemmy.world", "beehaw.org"])
        #expect(rows.first(where: { $0.accountKeychainId == "kc-1" })?.isDefault == true)
    }

    /// Service accounts are internal bookkeeping rows and must never appear in
    /// the account list exposed to the UI or Spotlight indexing.
    @Test
    func accountsSync_excludesServiceAccounts() async throws {
        let appDatabase = try AppDatabase.inMemory()
        try await appDatabase.writer.write { db in
            try Self.seedAccount(db, keychainId: "kc-user", host: "lemmy.world", isDefault: true, signedOut: false)
            // Insert a service account directly (seedAccount always sets isServiceAccount=0).
            try db.execute(sql: "INSERT INTO instance (actorId, createdAt) VALUES (?, ?)", arguments: ["https://service.test", Date()])
            let instanceId = db.lastInsertedRowID
            try db.execute(sql: "INSERT INTO site (instanceId, createdAt, updatedAt) VALUES (?, ?, ?)", arguments: [instanceId, Date(), Date()])
            let siteId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO account (siteId, accountKeychainId, isDefault, isServiceAccount, isSignedOutAccountType, createdAt, updatedAt)
                VALUES (?, 'kc-service', 0, 1, 0, ?, ?)
                """, arguments: [siteId, Date(), Date()])
        }
        let rows = appDatabase.accountsSync()
        #expect(rows.map(\.accountKeychainId) == ["kc-user"])
        #expect(!(rows.contains(where: { $0.accountKeychainId == "kc-service" })))
    }
}
