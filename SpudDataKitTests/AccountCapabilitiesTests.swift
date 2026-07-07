//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import GRDB
import Testing
@testable import SpudDataKit

struct AccountCapabilitiesTests {
    /// Seeds instance -> site(version) -> account rows the same way
    /// `AccountBlurNsfwTests` (and the other `*Sync` lookup tests) do, and
    /// returns the account's `accountKeychainId`.
    private func seedAccount(db: AppDatabase, siteVersion: String) async throws -> String {
        let keychainId = "keychain-capabilities-test"
        try await db.writer.write { db in
            var instance = InstanceRecord(actorId: "https://example.com")
            try instance.insert(db)
            var site = SiteRecord(instanceId: instance.id!, version: siteVersion)
            try site.insert(db)
            var account = AccountRecord(
                siteId: site.id!,
                accountKeychainId: keychainId,
                isSignedOutAccountType: false
            )
            try account.insert(db)
        }
        return keychainId
    }

    @Test
    func siteVersionResolvesThroughAccountJoin() async throws {
        let db = try AppDatabase.inMemory()
        let keychainId = try await seedAccount(db: db, siteVersion: "1.0.0-alpha.18")
        #expect(db.accountSiteVersionSync(forKeychainId: keychainId) == "1.0.0-alpha.18")
        let missing = db.accountSiteVersionSync(forKeychainId: "no-such-account")
        #expect(missing == nil)
    }
}
