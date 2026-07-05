//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import Testing
@testable import SpudDataKit

struct EphemeralAccountMigrationTests {
    /// After all migrations, the new columns exist and round-trip with defaults.
    @Test
    func newColumnsRoundTrip() async throws {
        let appDatabase = try AppDatabase.inMemory()
        try await appDatabase.writer.write { db in
            var instance = InstanceRecord(actorId: "https://example.com", createdAt: Date(), updatedAt: Date())
            try instance.insert(db)
            var site = SiteRecord(instanceId: instance.id!)
            try site.insert(db)
            var account = AccountRecord(
                siteId: site.id!,
                accountKeychainId: "k1",
                isSignedOutAccountType: true,
                isEphemeral: true
            )
            try account.insert(db)
        }
        let reread = try await appDatabase.writer.read { db in
            try AccountRecord.filter(Column("accountKeychainId") == "k1").fetchOne(db)
        }
        #expect(reread?.isEphemeral == true)
    }

    /// The v29 backfill flags a legacy (pre-v29) non-default signed-out account
    /// ephemeral, and leaves the default account untouched.
    @Test
    func backfillFlagsLegacyBrowseAccounts() async throws {
        // Build a raw queue and migrate only up to v28, insert legacy rows, then
        // migrate to v29 and assert the backfill result.
        let dbQueue = try DatabaseQueue()
        let migrator = AppDatabase.migrator
        try await migrator.migrate(dbQueue, upTo: "v28_postUnavailable")
        try await dbQueue.write { db in
            try db.execute(sql: "INSERT INTO instance (actorId, createdAt, updatedAt) VALUES ('https://a.example', 0, 0)")
            let instanceId = db.lastInsertedRowID
            try db.execute(sql: "INSERT INTO site (instanceId, createdAt, updatedAt) VALUES (?, 0, 0)", arguments: [instanceId])
            let siteId = db.lastInsertedRowID
            // legacy browse account (non-default signed-out) -> should become ephemeral
            try db.execute(sql: "INSERT INTO account (siteId, accountKeychainId, isDefault, isServiceAccount, isSignedOutAccountType, createdAt, updatedAt) VALUES (?, 'browse', 0, 0, 1, 0, 0)", arguments: [siteId])
            // default signed-out account -> should stay non-ephemeral
            try db.execute(sql: "INSERT INTO account (siteId, accountKeychainId, isDefault, isServiceAccount, isSignedOutAccountType, createdAt, updatedAt) VALUES (?, 'default', 1, 0, 1, 0, 0)", arguments: [siteId])
        }
        try await migrator.migrate(dbQueue) // apply v29
        try await dbQueue.read { db in
            let browse = try Int.fetchOne(db, sql: "SELECT isEphemeral FROM account WHERE accountKeychainId = 'browse'")
            let def = try Int.fetchOne(db, sql: "SELECT isEphemeral FROM account WHERE accountKeychainId = 'default'")
            #expect(browse == 1)
            #expect(def == 0)
        }
    }
}
