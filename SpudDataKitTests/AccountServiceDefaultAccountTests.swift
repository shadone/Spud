//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudUtilKit
import XCTest
@testable import SpudDataKit

@MainActor
final class AccountServiceDefaultAccountTests: XCTestCase {
    private func makeService() throws -> (AccountService, AppDatabase) {
        let db = try AppDatabase.inMemory()
        return (AccountService(appDatabase: db), db)
    }

    func test_emptyDatabase_returnsNil_doesNotCrash() throws {
        let (service, _) = try makeService()
        XCTAssertNil(service.currentDefaultAccountKeychainId())
    }

    func test_withAccount_returnsItsKeychainId() throws {
        let (service, db) = try makeService()
        let instance = try XCTUnwrap(InstanceActorId(from: "https://lemmy.world"))
        let keychainId = try db.ensureSignedOutAccountKeychainId(
            forInstance: instance,
            isServiceAccount: false
        )
        try db.setDefaultAccountSync(keychainId: keychainId)

        XCTAssertEqual(service.currentDefaultAccountKeychainId(), keychainId)
    }
}
