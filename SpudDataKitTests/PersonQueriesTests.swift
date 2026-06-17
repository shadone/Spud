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
        let personRowId: Int64 = try await appDatabase.writer.write { db in
            try db.execute(sql: "INSERT INTO instance (actorId, createdAt) VALUES ('https://lemmy.world', ?)", arguments: [Date()])
            let instanceId = db.lastInsertedRowID
            try db.execute(sql: "INSERT INTO site (instanceId, createdAt, updatedAt) VALUES (?, ?, ?)", arguments: [instanceId, Date(), Date()])
            let siteId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO person (siteId, personId, name, actorId, isAdmin, isBanned, isBotAccount, isDeleted, isLocal, numberOfPosts, numberOfComments, createdAt, updatedAt)
                VALUES (?, 42, 'alice', 'https://lemmy.world/u/alice', 0, 0, 0, 0, 1, 0, 0, ?, ?)
                """, arguments: [siteId, Date(), Date()])
            return db.lastInsertedRowID
        }
        XCTAssertEqual(appDatabase.personActorIdSync(forPersonRowId: personRowId), "https://lemmy.world/u/alice")
        XCTAssertNil(appDatabase.personActorIdSync(forPersonRowId: 999_999))
    }

    /// Regression: two federated sites each have a person with the same server-
    /// assigned `personId` (42) but different `actorId` values. `personActorIdSync`
    /// must return the correct actorId for each by keying on the unique primary key
    /// (`person.id`), not on the non-unique `personId` column.
    func test_personActorIdSync_disambiguatesBySiteWhenPersonIdCollides() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (rowIdA, rowIdB): (Int64, Int64) = try await appDatabase.writer.write { db in
            // Site A
            try db.execute(sql: "INSERT INTO instance (actorId, createdAt) VALUES ('https://a.test', ?)", arguments: [Date()])
            let instanceIdA = db.lastInsertedRowID
            try db.execute(sql: "INSERT INTO site (instanceId, createdAt, updatedAt) VALUES (?, ?, ?)", arguments: [instanceIdA, Date(), Date()])
            let siteIdA = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO person (siteId, personId, name, actorId, isAdmin, isBanned, isBotAccount, isDeleted, isLocal, numberOfPosts, numberOfComments, createdAt, updatedAt)
                VALUES (?, 42, 'x', 'https://a.test/u/x', 0, 0, 0, 0, 1, 0, 0, ?, ?)
                """, arguments: [siteIdA, Date(), Date()])
            let rA = db.lastInsertedRowID

            // Site B — same serverPersonId 42, different actorId
            try db.execute(sql: "INSERT INTO instance (actorId, createdAt) VALUES ('https://b.test', ?)", arguments: [Date()])
            let instanceIdB = db.lastInsertedRowID
            try db.execute(sql: "INSERT INTO site (instanceId, createdAt, updatedAt) VALUES (?, ?, ?)", arguments: [instanceIdB, Date(), Date()])
            let siteIdB = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO person (siteId, personId, name, actorId, isAdmin, isBanned, isBotAccount, isDeleted, isLocal, numberOfPosts, numberOfComments, createdAt, updatedAt)
                VALUES (?, 42, 'x', 'https://b.test/u/x', 0, 0, 0, 0, 1, 0, 0, ?, ?)
                """, arguments: [siteIdB, Date(), Date()])
            let rB = db.lastInsertedRowID
            return (rA, rB)
        }
        XCTAssertEqual(appDatabase.personActorIdSync(forPersonRowId: rowIdA), "https://a.test/u/x")
        XCTAssertEqual(appDatabase.personActorIdSync(forPersonRowId: rowIdB), "https://b.test/u/x")
    }
}
