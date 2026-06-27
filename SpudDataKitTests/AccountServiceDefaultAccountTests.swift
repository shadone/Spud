//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudUtilKit
import Testing
@testable import SpudDataKit

@MainActor
struct AccountServiceDefaultAccountTests {
    private func makeService() throws -> (AccountService, AppDatabase) {
        let db = try AppDatabase.inMemory()
        return (AccountService(appDatabase: db), db)
    }

    @Test
    func emptyDatabase_returnsNil_doesNotCrash() throws {
        let (service, _) = try makeService()
        #expect(service.currentDefaultAccountKeychainId() == nil)
    }

    @Test
    func withAccount_returnsItsKeychainId() throws {
        let (service, db) = try makeService()
        let instance = try #require(InstanceActorId(from: "https://lemmy.world"))
        let keychainId = try db.ensureSignedOutAccountKeychainId(
            forInstance: instance,
            isServiceAccount: false
        )
        try db.setDefaultAccountSync(keychainId: keychainId)

        #expect(service.currentDefaultAccountKeychainId() == keychainId)
    }
}
