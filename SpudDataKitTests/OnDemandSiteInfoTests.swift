//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import Testing
@testable import SpudDataKit

struct OnDemandSiteInfoTests {
    private func seed(_ appDatabase: AppDatabase, keychainId: String, isEphemeral: Bool, siteName: String?) async throws {
        try await appDatabase.writer.write { db in
            var inst = InstanceRecord(actorId: "https://\(keychainId).example", createdAt: Date(), updatedAt: Date())
            try inst.insert(db)
            var site = SiteRecord(instanceId: inst.id!, name: siteName)
            try site.insert(db)
            var acct = AccountRecord(siteId: site.id!, accountKeychainId: keychainId, isSignedOutAccountType: true, isEphemeral: isEphemeral)
            try acct.insert(db)
        }
    }

    @Test
    func ephemeralWithMissingSiteInfoShouldFetch() async throws {
        let appDatabase = try AppDatabase.inMemory()
        try await seed(appDatabase, keychainId: "browse", isEphemeral: true, siteName: nil)
        #expect(appDatabase.shouldFetchSiteInfoOnDemandSync(forAccountKeychainId: "browse") == true)
    }

    @Test
    func ephemeralWithSiteInfoDoesNotFetch() async throws {
        let appDatabase = try AppDatabase.inMemory()
        try await seed(appDatabase, keychainId: "browse", isEphemeral: true, siteName: "Aussie Zone")
        #expect(appDatabase.shouldFetchSiteInfoOnDemandSync(forAccountKeychainId: "browse") == false)
    }

    @Test
    func nonEphemeralDoesNotFetch() async throws {
        let appDatabase = try AppDatabase.inMemory()
        try await seed(appDatabase, keychainId: "real", isEphemeral: false, siteName: nil)
        #expect(appDatabase.shouldFetchSiteInfoOnDemandSync(forAccountKeychainId: "real") == false)
    }
}
