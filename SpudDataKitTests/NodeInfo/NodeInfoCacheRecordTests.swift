//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import Testing
@testable import SpudDataKit

struct NodeInfoCacheRecordTests {
    @Test
    func upsertsAndFetchesByHost() async throws {
        let appDatabase = try AppDatabase.inMemory()
        try await appDatabase.writer.write { db in
            var record = NodeInfoCacheRecord(
                host: "lemmy.world", softwareName: "lemmy",
                softwareVersion: "0.19.5", fetchedAt: Date(timeIntervalSince1970: 1000)
            )
            try record.upsert(db)
            // Upsert on the same host replaces, not duplicates.
            var updated = record
            updated.softwareVersion = "0.19.6"
            try updated.upsert(db)
        }
        let rows = try await appDatabase.writer.read { db in
            try NodeInfoCacheRecord.fetchAll(db)
        }
        #expect(rows.count == 1)
        #expect(rows.first?.softwareVersion == "0.19.6")
    }

    /// The v31 metadata columns round-trip: a populated row reads back its
    /// usage counters, and an all-nil-metadata row reads back all `nil`.
    @Test
    func metadataColumnsRoundTrip() async throws {
        let appDatabase = try AppDatabase.inMemory()
        try await appDatabase.writer.write { db in
            var populated = NodeInfoCacheRecord(
                host: "lemmy.world", softwareName: "lemmy",
                softwareVersion: "0.19.5", fetchedAt: Date(timeIntervalSince1970: 1000),
                openRegistrations: true,
                usersTotal: 1000, usersActiveMonth: 200, usersActiveHalfyear: 500,
                localPosts: 3000, localComments: 9000
            )
            try populated.upsert(db)
            // A row that omits every usage field (default-nil memberwise init).
            var bare = NodeInfoCacheRecord(
                host: "bare.example", softwareName: "piefed",
                softwareVersion: nil, fetchedAt: Date(timeIntervalSince1970: 2000)
            )
            try bare.upsert(db)
        }
        let populated = try #require(try await appDatabase.writer.read { db in
            try NodeInfoCacheRecord.filter(key: "lemmy.world").fetchOne(db)
        })
        #expect(populated.openRegistrations == true)
        #expect(populated.usersTotal == 1000)
        #expect(populated.usersActiveMonth == 200)
        #expect(populated.usersActiveHalfyear == 500)
        #expect(populated.localPosts == 3000)
        #expect(populated.localComments == 9000)

        let bare = try #require(try await appDatabase.writer.read { db in
            try NodeInfoCacheRecord.filter(key: "bare.example").fetchOne(db)
        })
        #expect(bare.openRegistrations == nil)
        #expect(bare.usersTotal == nil)
        #expect(bare.usersActiveMonth == nil)
        #expect(bare.usersActiveHalfyear == nil)
        #expect(bare.localPosts == nil)
        #expect(bare.localComments == nil)
    }
}
