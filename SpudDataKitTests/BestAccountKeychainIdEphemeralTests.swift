//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import SpudUtilKit
import Testing
@testable import SpudDataKit

struct BestAccountKeychainIdEphemeralTests {
    @Test
    func autoCreatedBrowseAccountIsEphemeral() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let instance = try #require(InstanceActorId(from: "https://aussie.zone"))
        let keychainId = try appDatabase.bestAccountKeychainId(forInstance: instance)
        let account = try await appDatabase.writer.read { db in
            try AccountRecord.filter(Column("accountKeychainId") == keychainId).fetchOne(db)
        }
        #expect(account?.isEphemeral == true)
        #expect(account?.isSignedOutAccountType == true)
    }

    @Test
    func existingDefaultAccountIsReusedAndNotFlagged() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let instance = try #require(InstanceActorId(from: "https://lemmy.world"))
        // Seed a default signed-out account for the site.
        try await appDatabase.writer.write { db in
            var inst = InstanceRecord(actorId: instance.actorId, createdAt: Date(), updatedAt: Date())
            try inst.insert(db)
            var site = SiteRecord(instanceId: inst.id!)
            try site.insert(db)
            var acct = AccountRecord(siteId: site.id!, accountKeychainId: "default", isDefault: true, isSignedOutAccountType: true)
            try acct.insert(db)
        }
        let keychainId = try appDatabase.bestAccountKeychainId(forInstance: instance)
        #expect(keychainId == "default")
        let account = try await appDatabase.writer.read { db in
            try AccountRecord.filter(Column("accountKeychainId") == "default").fetchOne(db)
        }
        #expect(account?.isEphemeral == false)
    }
}
