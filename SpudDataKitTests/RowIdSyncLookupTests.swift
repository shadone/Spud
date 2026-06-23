//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import XCTest
@testable import SpudDataKit

/// Tests for the account-keyed row-id sync helpers:
///   - `personRowIdSync(forKeychainId:personId:)`
///   - `communityRowIdSync(forAccountId:serverCommunityId:)`
final class RowIdSyncLookupTests: XCTestCase {
    private var appDatabase: AppDatabase!

    override func setUpWithError() throws {
        appDatabase = try AppDatabase.inMemory()
    }

    override func tearDown() {
        appDatabase = nil
    }

    // MARK: - Helpers

    /// Seeds an instance, site, and account with the given keychainId.
    /// Returns (siteId, accountId).
    private func seedInstanceSiteAccount(
        keychainId: String,
        instanceActorId: String = "https://example.com"
    ) async throws -> (siteId: Int64, accountId: Int64) {
        try await appDatabase.writer.write { db in
            var instance = InstanceRecord(actorId: instanceActorId)
            try instance.insert(db)

            var site = SiteRecord(instanceId: instance.id!)
            try site.insert(db)

            var account = AccountRecord(
                siteId: site.id!,
                accountKeychainId: keychainId,
                isSignedOutAccountType: false
            )
            try account.insert(db)

            return (site.id!, account.id!)
        }
    }

    // MARK: - personRowIdSync(forKeychainId:personId:)

    /// Person stored under account's site is found by (keychainId, personId).
    func testPersonRowIdSyncByKeychainIdFindsPersonUnderAccountSite() async throws {
        let keychainId = "test-keychain-1"
        let (siteId, _) = try await seedInstanceSiteAccount(keychainId: keychainId)

        let serverPersonId: Int64 = 77
        let personRowId: Int64 = try await appDatabase.writer.write { db in
            var person = PersonRecord(
                siteId: siteId,
                personId: serverPersonId,
                name: "alice",
                actorId: "https://example.com/u/alice"
            )
            try person.insert(db)
            return person.id!
        }

        // Known keychainId + personId -> returns the row id.
        let result = appDatabase.personRowIdSync(forKeychainId: keychainId, personId: serverPersonId)
        XCTAssertEqual(result, personRowId)

        // Unknown personId -> nil.
        let missingPersonId = appDatabase.personRowIdSync(forKeychainId: keychainId, personId: 9999)
        XCTAssertNil(missingPersonId)

        // Unknown keychainId -> nil.
        let missingKeychainId = appDatabase.personRowIdSync(forKeychainId: "no-such-keychain", personId: serverPersonId)
        XCTAssertNil(missingKeychainId)
    }

    /// Regression: a federated (remote) person has an actorId on a different
    /// host than the account's home instance, but is still stored under the
    /// ACCOUNT's siteId. The account-keyed lookup must still find it; the old
    /// instance-keyed lookup (personRowIdSync(instanceActorId:personId:)) would
    /// fail because it joins through instance.actorId which won't match the
    /// person's remote host.
    func testPersonRowIdSyncByKeychainIdIgnoresPersonHomeInstance() async throws {
        let keychainId = "test-keychain-2"
        // Account's home instance is "https://example.com".
        let (siteId, _) = try await seedInstanceSiteAccount(
            keychainId: keychainId,
            instanceActorId: "https://example.com"
        )

        // Bob lives on a remote instance but is stored under the account's site.
        let serverPersonId: Int64 = 42
        let personRowId: Int64 = try await appDatabase.writer.write { db in
            var person = PersonRecord(
                siteId: siteId,
                personId: serverPersonId,
                name: "bob",
                actorId: "https://remote.example/u/bob" // different host from account's instance
            )
            try person.insert(db)
            return person.id!
        }

        // Account-keyed lookup finds the remote person via the account's siteId.
        let result = appDatabase.personRowIdSync(forKeychainId: keychainId, personId: serverPersonId)
        XCTAssertEqual(result, personRowId)

        // Confirm the old instance-keyed helper would NOT find it (the regression
        // scenario): bob's actorId is on remote.example, not example.com.
        let oldLookup = appDatabase.personRowIdSync(
            instanceActorId: "https://remote.example",
            personId: serverPersonId
        )
        XCTAssertNil(oldLookup, "Old instance-keyed lookup must not find a person stored under a different site")
    }

    // MARK: - communityRowIdSync(forAccountId:serverCommunityId:)

    /// Community stored under an account is found by (accountId, serverCommunityId).
    func testCommunityRowIdSyncFindsByAccountAndServerId() async throws {
        let keychainId = "test-keychain-3"
        let (_, accountId) = try await seedInstanceSiteAccount(keychainId: keychainId)

        let serverCommunityId: Int64 = 55
        let communityRowId: Int64 = try await appDatabase.writer.write { db in
            var community = CommunityRecord(
                accountId: accountId,
                communityId: serverCommunityId,
                name: "testcommunity"
            )
            try community.insert(db)
            return community.id!
        }

        // Known accountId + serverCommunityId -> returns the row id.
        let result = appDatabase.communityRowIdSync(
            forAccountId: accountId,
            serverCommunityId: serverCommunityId
        )
        XCTAssertEqual(result, communityRowId)

        // Unknown serverCommunityId -> nil.
        let missingCommunity = appDatabase.communityRowIdSync(
            forAccountId: accountId,
            serverCommunityId: 9999
        )
        XCTAssertNil(missingCommunity)

        // Unknown accountId -> nil.
        let missingAccount = appDatabase.communityRowIdSync(
            forAccountId: 9999,
            serverCommunityId: serverCommunityId
        )
        XCTAssertNil(missingAccount)
    }
}
