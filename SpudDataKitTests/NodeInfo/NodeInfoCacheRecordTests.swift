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
}
