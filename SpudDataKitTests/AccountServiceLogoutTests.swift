//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import LemmyKit
import XCTest
@testable import SpudDataKit

/// Tests for `AccountService.logout`: it removes the account row from the
/// database and switches the default to another registered account, or to the
/// signed-out account on the same instance when no other account exists.
@MainActor
final class AccountServiceLogoutTests: XCTestCase {
    private var appDatabase: AppDatabase!
    private var sut: AccountService!

    override func setUpWithError() throws {
        appDatabase = try AppDatabase.inMemory()
        sut = AccountService(appDatabase: appDatabase)
    }

    override func tearDown() {
        sut = nil
        appDatabase = nil
    }

    /// Seeds one instance/site with the given accounts. Returns the keychain
    /// ids in insertion order.
    @discardableResult
    private func seed(
        accounts: [(keychainId: String, isSignedOut: Bool, isDefault: Bool)]
    ) async throws -> Int64 {
        try await appDatabase.writer.write { db -> Int64 in
            var instance = InstanceRecord(actorId: "https://example.com")
            try instance.insert(db)
            var site = SiteRecord(instanceId: instance.id!)
            try site.insert(db)
            for account in accounts {
                var record = AccountRecord(
                    siteId: site.id!,
                    accountKeychainId: account.keychainId,
                    isDefault: account.isDefault,
                    isSignedOutAccountType: account.isSignedOut
                )
                try record.insert(db)
            }
            return site.id!
        }
    }

    private func accountExists(keychainId: String) throws -> Bool {
        try appDatabase.writer.read { db in
            try AccountRecord
                .filter(Column("accountKeychainId") == keychainId)
                .fetchCount(db) > 0
        }
    }

    private func defaultKeychainId() throws -> String? {
        try appDatabase.writer.read { db in
            try AccountRecord
                .filter(Column("isDefault") == true)
                .fetchOne(db)?
                .accountKeychainId
        }
    }

    func testLogoutRemovesAccountRow() async throws {
        try await seed(accounts: [
            (keychainId: "signed-in-1", isSignedOut: false, isDefault: true),
            (keychainId: "signed-out", isSignedOut: true, isDefault: false),
        ])

        sut.logout(forAccountKeychainId: "signed-in-1")

        XCTAssertFalse(try accountExists(keychainId: "signed-in-1"), "logout should delete the account row")
    }

    func testLogoutSwitchesDefaultToAnotherSignedInAccount() async throws {
        try await seed(accounts: [
            (keychainId: "signed-in-1", isSignedOut: false, isDefault: true),
            (keychainId: "signed-in-2", isSignedOut: false, isDefault: false),
            (keychainId: "signed-out", isSignedOut: true, isDefault: false),
        ])

        sut.logout(forAccountKeychainId: "signed-in-1")

        // The remaining signed-in account is preferred over the signed-out one.
        XCTAssertEqual(try defaultKeychainId(), "signed-in-2")
        XCTAssertTrue(try accountExists(keychainId: "signed-in-2"))
        XCTAssertTrue(try accountExists(keychainId: "signed-out"))
    }

    func testLogoutFallsBackToSignedOutAccountWhenNoOtherSignedInAccount() async throws {
        try await seed(accounts: [
            (keychainId: "signed-in-1", isSignedOut: false, isDefault: true),
            (keychainId: "signed-out", isSignedOut: true, isDefault: false),
        ])

        sut.logout(forAccountKeychainId: "signed-in-1")

        XCTAssertFalse(try accountExists(keychainId: "signed-in-1"))
        XCTAssertEqual(try defaultKeychainId(), "signed-out", "logout should fall back to the signed-out account")
    }

    func testLogoutIsNoOpForSignedOutAccount() async throws {
        try await seed(accounts: [
            (keychainId: "signed-out", isSignedOut: true, isDefault: true),
        ])

        sut.logout(forAccountKeychainId: "signed-out")

        XCTAssertTrue(try accountExists(keychainId: "signed-out"), "logout should not remove a signed-out account")
    }
}
