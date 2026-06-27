//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import Testing
@testable import SpudDataKit

/// `searchExplorerInstancesSync` — the client-side instance search that backs
/// the Search screen's `.instances` scope. Seeds a handful of Explorer instance
/// rows into an in-memory database and asserts substring matching (on both
/// `baseurl` and `name`), user-count ordering, the result limit, and the
/// empty-query short circuit.
struct ExplorerInstanceSearchTests {
    private func makeDatabase(_ rows: [ExplorerInstanceRecord]) throws -> AppDatabase {
        let appDatabase = try AppDatabase.inMemory()
        try appDatabase.writer.write { db in
            for var row in rows {
                try row.insert(db, onConflict: .replace)
            }
        }
        return appDatabase
    }

    private func record(
        _ baseurl: String,
        name: String,
        users: Int64
    ) -> ExplorerInstanceRecord {
        ExplorerInstanceRecord(baseurl: baseurl, name: name, usersTotal: users)
    }

    @Test
    func matchesBaseurlSubstring_orderedByUsersDescending() throws {
        let appDatabase = try makeDatabase([
            record("programming.dev", name: "Programming.dev", users: 5000),
            record("lemmy.world", name: "Lemmy World", users: 99000),
            record("sopuli.xyz", name: "Sopuli", users: 8000),
            record("prog.example", name: "Prog Example", users: 100),
        ])

        let results = appDatabase.searchExplorerInstancesSync(query: "prog")

        // Both "programming.dev" and "prog.example" match on baseurl; ordered by
        // total users (largest first). lemmy.world / sopuli.xyz do not match.
        #expect(results.map(\.baseurl) == ["programming.dev", "prog.example"])
    }

    @Test
    func matchesNameSubstring_caseInsensitive() throws {
        let appDatabase = try makeDatabase([
            record("lemmy.world", name: "Lemmy World", users: 99000),
            record("beehaw.org", name: "Beehaw", users: 12000),
        ])

        // Query casing differs from the stored name; LIKE is case-insensitive.
        let results = appDatabase.searchExplorerInstancesSync(query: "BEEHAW")

        #expect(results.map(\.baseurl) == ["beehaw.org"])
    }

    @Test
    func respectsLimit() throws {
        let rows = (1...10).map { i in
            record("instance\(i).test", name: "Instance \(i)", users: Int64(i))
        }
        let appDatabase = try makeDatabase(rows)

        let results = appDatabase.searchExplorerInstancesSync(query: "instance", limit: 3)

        #expect(results.count == 3)
        // Highest user counts win under the limit (10, 9, 8).
        #expect(results.map(\.baseurl) == ["instance10.test", "instance9.test", "instance8.test"])
    }

    @Test
    func emptyQueryReturnsNothing() throws {
        let appDatabase = try makeDatabase([
            record("lemmy.world", name: "Lemmy World", users: 99000),
        ])

        #expect(appDatabase.searchExplorerInstancesSync(query: "").isEmpty)
        #expect(appDatabase.searchExplorerInstancesSync(query: "   ").isEmpty)
    }

    @Test
    func noMatchReturnsEmpty() throws {
        let appDatabase = try makeDatabase([
            record("lemmy.world", name: "Lemmy World", users: 99000),
        ])

        #expect(appDatabase.searchExplorerInstancesSync(query: "nonexistent").isEmpty)
    }
}
