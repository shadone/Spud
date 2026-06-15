//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import GRDB
import XCTest
@testable import SpudDataKit

final class AppDatabaseTests: XCTestCase {
    private var sut: AppDatabase!

    override func setUpWithError() throws {
        sut = try AppDatabase.inMemory()
    }

    override func tearDown() {
        sut = nil
    }

    func testMigratorCreatesAllExpectedTables() throws {
        let tableNames = try sut.writer.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name"
            )
        }

        let appTables = tableNames.filter { !$0.hasPrefix("grdb_") && !$0.hasPrefix("sqlite_") }

        XCTAssertEqual(
            Set(appTables),
            Set([
                "account",
                "accountFollowedCommunity",
                "comment",
                "commentElement",
                "community",
                "explorerCommunity",
                "explorerDatasetMeta",
                "explorerInstance",
                "feed",
                "instance",
                "mutedCommunity",
                "nodeInfo",
                "page",
                "pageElement",
                "person",
                "post",
                "postInteraction",
                "site",
            ])
        )
    }

    func testInstanceRoundTrip() throws {
        let inserted = try sut.writer.write { db -> InstanceRecord in
            var record = InstanceRecord(actorId: "https://lemmy.world")
            try record.insert(db)
            return record
        }
        XCTAssertNotNil(inserted.id)

        let fetched = try sut.writer.read { db in
            try InstanceRecord.fetchOne(db, key: inserted.id!)
        }
        XCTAssertEqual(fetched?.actorId, "https://lemmy.world")
    }

    func testCascadeDeleteFromInstanceClearsDependentRows() throws {
        let (instanceId, accountId) = try sut.writer.write { db -> (Int64, Int64) in
            var instance = InstanceRecord(actorId: "https://lemmy.world")
            try instance.insert(db)

            var site = SiteRecord(instanceId: instance.id!)
            try site.insert(db)

            var account = AccountRecord(
                siteId: site.id!,
                accountKeychainId: "keychain-1"
            )
            try account.insert(db)

            return (instance.id!, account.id!)
        }

        try sut.writer.write { db in
            _ = try InstanceRecord.deleteOne(db, key: instanceId)
        }

        let remainingAccount = try sut.writer.read { db in
            try AccountRecord.fetchOne(db, key: accountId)
        }
        XCTAssertNil(remainingAccount, "Account should cascade-delete with its site/instance")
    }

    func testUniqueAccountKeychainIdEnforced() throws {
        let siteId = try sut.writer.write { db -> Int64 in
            var instance = InstanceRecord(actorId: "https://lemmy.world")
            try instance.insert(db)
            var site = SiteRecord(instanceId: instance.id!)
            try site.insert(db)
            return site.id!
        }

        try sut.writer.write { db in
            var account = AccountRecord(siteId: siteId, accountKeychainId: "shared")
            try account.insert(db)
        }

        XCTAssertThrowsError(
            try sut.writer.write { db in
                var dup = AccountRecord(siteId: siteId, accountKeychainId: "shared")
                try dup.insert(db)
            }
        )
    }
}
