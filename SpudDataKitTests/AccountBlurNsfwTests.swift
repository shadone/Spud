//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import GRDB
import Testing
@testable import SpudDataKit

struct AccountBlurNsfwTests {
    @Test
    func setAccountBlurNsfw_mirrorsOntoAccountRow() async throws {
        let appDatabase = try AppDatabase.inMemory()

        let keychainId = "keychain-blur-nsfw-test"
        try await appDatabase.writer.write { db in
            var instance = InstanceRecord(actorId: "https://example.com")
            try instance.insert(db)
            var site = SiteRecord(instanceId: instance.id!)
            try site.insert(db)
            var account = AccountRecord(
                siteId: site.id!,
                accountKeychainId: keychainId,
                isSignedOutAccountType: false
            )
            try account.insert(db)
        }

        try await appDatabase.setAccountBlurNsfw(false, forKeychainId: keychainId)

        let account = try await appDatabase.writer.read { db in
            try AccountRecord.filter(Column("accountKeychainId") == keychainId).fetchOne(db)
        }
        #expect(account?.blurNsfw == false)
    }
}
