//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import XCTest
@testable import SpudDataKit

final class PersonQueriesTests: XCTestCase {
    func test_personActorIdSync_returnsActorId() async throws {
        let appDatabase = try AppDatabase.inMemory()
        try await appDatabase.writer.write { db in
            try db.execute(sql: "INSERT INTO instance (actorId, createdAt) VALUES ('https://lemmy.world', ?)", arguments: [Date()])
            let instanceId = db.lastInsertedRowID
            try db.execute(sql: "INSERT INTO site (instanceId, createdAt, updatedAt) VALUES (?, ?, ?)", arguments: [instanceId, Date(), Date()])
            let siteId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO person (siteId, personId, name, actorId, isAdmin, isBanned, isBotAccount, isDeleted, isLocal, numberOfPosts, numberOfComments, createdAt, updatedAt)
                VALUES (?, 42, 'alice', 'https://lemmy.world/u/alice', 0, 0, 0, 0, 1, 0, 0, ?, ?)
                """, arguments: [siteId, Date(), Date()])
        }
        XCTAssertEqual(appDatabase.personActorIdSync(forServerPersonId: 42), "https://lemmy.world/u/alice")
        XCTAssertNil(appDatabase.personActorIdSync(forServerPersonId: 999))
    }
}
