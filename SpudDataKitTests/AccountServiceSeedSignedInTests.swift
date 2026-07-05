//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import LemmyKit
import SpudUtilKit
import Testing
@testable import SpudDataKit

/// In-memory `CredentialStore` standing in for the keychain, which the test
/// bundle can't reach (no shared-group entitlement). Records stored credentials
/// so the seed's persistence can be asserted.
private final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: LemmyCredential] = [:]

    func credential(forKeychainId keychainId: String) -> LemmyCredential? {
        lock.withLock { storage[keychainId] }
    }

    func setCredential(_ credential: LemmyCredential, forKeychainId keychainId: String) {
        lock.withLock { storage[keychainId] = credential }
    }

    func removeCredential(forKeychainId keychainId: String) {
        lock.withLock { _ = storage.removeValue(forKey: keychainId) }
    }

    var count: Int {
        lock.withLock { storage.count }
    }
}

/// Tests for the DEBUG-only UI-test seam `AccountService.seedSignedInDefaultAccount`.
/// It creates a signed-IN default account (instance + site + local person +
/// account row) under a fixed keychain id and stores a fake JWT — so a UI test
/// can launch straight into the signed-in app without a live login. The seed
/// never touches the network, so an injected in-memory credential store and a
/// trapping `makeApi` fully exercise it offline.
@MainActor
struct AccountServiceSeedSignedInTests {
    private var appDatabase: AppDatabase

    init() throws {
        appDatabase = try AppDatabase.inMemory()
    }

    /// Builds the service with an injected in-memory credential store. The seed
    /// never hits the network, so `makeApi` traps if the seam ever tries to
    /// build a `LemmyApi`.
    private func makeSUT(credentialStore: CredentialStore) -> AccountService {
        AccountService(
            appDatabase: appDatabase,
            credentialStore: credentialStore
        ) { _, _ in
            fatalError("seedSignedInDefaultAccount must not build a LemmyApi")
        }
    }

    private func exampleInstance() throws -> InstanceActorId {
        try #require(InstanceActorId(from: "https://example.com"))
    }

    private func accountRecord(forKeychainId keychainId: String) throws -> AccountRecord? {
        try appDatabase.writer.read { db in
            try AccountRecord
                .filter(Column("accountKeychainId") == keychainId)
                .fetchOne(db)
        }
    }

    private func personRecord(id: Int64) throws -> PersonRecord? {
        try appDatabase.writer.read { db in
            try PersonRecord.fetchOne(db, key: id)
        }
    }

    /// The seed creates a signed-in default account under the fixed keychain id,
    /// whose `personId` resolves to a local person row (so the Account tab
    /// resolves a header instead of spinning).
    @Test
    func seed_createsSignedInDefaultAccount() throws {
        let sut = makeSUT(credentialStore: InMemoryCredentialStore())
        let instance = try exampleInstance()

        sut.seedSignedInDefaultAccount(atInstance: instance)

        let expectedId = AccountService.uiTestSignedInKeychainId
        #expect(sut.currentDefaultAccountKeychainId() == expectedId)
        #expect(sut.isSignedOut(forAccountKeychainId: expectedId) == false)

        let account = try #require(try accountRecord(forKeychainId: expectedId))
        let personId = try #require(account.personId, "seeded account must carry a personId")
        let person = try #require(try personRecord(id: personId), "personId must resolve to a person row")
        #expect(person.name == "uitester")
        #expect(person.isLocal)
    }

    /// The seed persists a fake JWT credential under the fixed keychain id.
    @Test
    func seed_writesFakeJwtCredential() throws {
        let credentialStore = InMemoryCredentialStore()
        let sut = makeSUT(credentialStore: credentialStore)
        let instance = try exampleInstance()

        sut.seedSignedInDefaultAccount(atInstance: instance)

        let stored = credentialStore.credential(forKeychainId: AccountService.uiTestSignedInKeychainId)
        #expect(
            stored?.toString() == LemmyCredential(jwt: "fake-jwt").toString(),
            "the seed should store a fake-jwt credential for the fixed keychain id"
        )
    }

    /// The seed no-ops when a default account already exists: signing in as
    /// signed-out first, then seeding, leaves the signed-out account as the
    /// default and writes no signed-in credential.
    @Test
    func seed_isIdempotent_whenDefaultAccountExists() throws {
        let credentialStore = InMemoryCredentialStore()
        let sut = makeSUT(credentialStore: credentialStore)
        let instance = try exampleInstance()

        sut.signInAsSignedOut(atInstance: instance)
        let signedOutDefault = try #require(sut.currentDefaultAccountKeychainId())

        sut.seedSignedInDefaultAccount(atInstance: instance)

        // Still the signed-out account; the seed did not take over the default.
        #expect(sut.currentDefaultAccountKeychainId() == signedOutDefault)
        #expect(sut.isSignedOut(forAccountKeychainId: signedOutDefault))
        // No signed-in seed account row, and no credential written.
        #expect(try accountRecord(forKeychainId: AccountService.uiTestSignedInKeychainId) == nil)
        // swiftformat:disable:next isEmpty
        #expect(credentialStore.count == 0)
    }
}
