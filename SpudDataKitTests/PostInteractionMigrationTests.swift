//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import XCTest
@testable import SpudDataKit

final class PostInteractionMigrationTests: XCTestCase {
    func testPostInteractionTableExistsAfterMigration() throws {
        let appDatabase = try AppDatabase.inMemory()
        let exists = try appDatabase.writer.read { db in
            try db.tableExists("postInteraction")
        }
        XCTAssertTrue(exists)
    }

    func testUniqueOnAccountAndPostServerId() throws {
        let appDatabase = try AppDatabase.inMemory()
        try appDatabase.writer.write { db in
            try db.execute(sql: "INSERT INTO instance (actorId, createdAt) VALUES ('https://a.test', ?)", arguments: [Date()])
            let instanceId = db.lastInsertedRowID
            try db.execute(sql: "INSERT INTO site (instanceId, createdAt, updatedAt) VALUES (?, ?, ?)", arguments: [instanceId, Date(), Date()])
            let siteId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO account (siteId, accountKeychainId, isDefault, isServiceAccount, isSignedOutAccountType, createdAt, updatedAt)
                VALUES (?, 'kc-1', 0, 0, 0, ?, ?)
                """, arguments: [siteId, Date(), Date()])
            let accountId = db.lastInsertedRowID

            var first = PostInteractionRecord(accountId: accountId, postServerId: 100)
            try first.insert(db)
        }

        try appDatabase.writer.write { db in
            let accountId = try Int64.fetchOne(db, sql: "SELECT id FROM account LIMIT 1")!
            var duplicate = PostInteractionRecord(accountId: accountId, postServerId: 100)
            XCTAssertThrowsError(try duplicate.insert(db))
        }
    }
}
