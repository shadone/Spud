//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudUtilKit
import Testing
@testable import SpudDataKit

/// Round-trips the per-account default POST sort type through `AccountService`.
/// The getter (`defaultSortType`) reads `AccountRecord.defaultSortType`; the
/// setter must persist to the same column so the value survives a relaunch
/// (a fresh `AccountService` over the same database reads it back).
@MainActor
struct AccountServiceDefaultSortTypeTests {
    private func makeService() throws -> (AccountService, AppDatabase) {
        let db = try AppDatabase.inMemory()
        return (AccountService(appDatabase: db), db)
    }

    private func makeAccount(_ db: AppDatabase) throws -> String {
        let instance = try #require(InstanceActorId(from: "https://lemmy.world"))
        return try db.ensureSignedOutAccountKeychainId(
            forInstance: instance,
            isServiceAccount: false
        )
    }

    /// A freshly created account has no stored sort, so the getter falls back
    /// to `.Hot`.
    @Test
    func baseline_returnsHot() throws {
        let (service, db) = try makeService()
        let keychainId = try makeAccount(db)

        #expect(service.defaultSortType(forAccountKeychainId: keychainId) == .Hot)
    }

    /// Setting the default sort persists it: the same service reads back the
    /// new value.
    @Test
    func setDefaultSortType_roundTrips() throws {
        let (service, db) = try makeService()
        let keychainId = try makeAccount(db)

        service.setDefaultSortType(.New, forAccountKeychainId: keychainId)

        #expect(service.defaultSortType(forAccountKeychainId: keychainId) == .New)
    }

    /// Persistence is on the account record, so a brand-new `AccountService`
    /// over the same database (mirroring an app relaunch) reads the value the
    /// previous instance wrote.
    @Test
    func setDefaultSortType_survivesNewService() throws {
        let (service, db) = try makeService()
        let keychainId = try makeAccount(db)

        service.setDefaultSortType(.New, forAccountKeychainId: keychainId)

        let relaunched = AccountService(appDatabase: db)
        #expect(relaunched.defaultSortType(forAccountKeychainId: keychainId) == .New)
    }
}
