//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudUtilKit
import Testing
@testable import SpudDataKit

@MainActor
struct AccountScopeTests {
    private func makeService() throws -> (AccountService, AppDatabase, String) {
        let db = try AppDatabase.inMemory()
        let service = AccountService(appDatabase: db)
        let instance = try #require(InstanceActorId(from: "https://lemmy.world"))
        let keychainId = try db.ensureSignedOutAccountKeychainId(
            forInstance: instance,
            isServiceAccount: false
        )
        return (service, db, keychainId)
    }

    @Test
    func scope_carriesRequestedKeychainId() throws {
        let (service, _, keychainId) = try makeService()

        let scope = service.scope(forAccountKeychainId: keychainId)

        #expect(scope.accountKeychainId == keychainId)
    }

    @Test
    func scope_vendsTheSameCachedLemmyService() throws {
        let (service, _, keychainId) = try makeService()

        let scope = service.scope(forAccountKeychainId: keychainId)
        let direct = service.lemmyService(forAccountKeychainId: keychainId)

        // The scope is a handle over the existing per-account cache, not a
        // parallel service: both must be the same actor instance.
        #expect(scope.lemmyService === direct)
    }

    @Test
    func scope_reportsSignedOutStatus() throws {
        let (service, _, keychainId) = try makeService()

        // makeService() registers a signed-out account.
        #expect(service.scope(forAccountKeychainId: keychainId).isSignedOut)
    }

    @Test
    func scope_reportsSignedInStatus() async throws {
        let db = try AppDatabase.inMemory()
        let service = AccountService(appDatabase: db)
        let instance = try #require(InstanceActorId(from: "https://lemmy.world"))
        let (_, siteId) = try await db.ensureSite(forInstance: instance)
        let keychainId = "signed-in-account"
        _ = try await db.ensureAccount(
            keychainId: keychainId,
            siteId: siteId,
            isSignedOut: false,
            isServiceAccount: false
        )

        // A signed-in account reports isSignedOut == false. This cannot pass via
        // isSignedOut(forAccountKeychainId:)'s `?? true` missing-row fallback, so
        // it genuinely exercises the signed-in path (which makeService never does).
        #expect(!(service.scope(forAccountKeychainId: keychainId).isSignedOut))
    }

    @Test
    func scope_reportsInstanceActorId() throws {
        let (service, _, keychainId) = try makeService()

        #expect(service.scope(forAccountKeychainId: keychainId).instanceActorId?.host == "lemmy.world")
    }
}
