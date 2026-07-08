//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import Testing
@testable import SpudDataKit

struct NodeInfoMetadataMigrationTests {
    /// After all migrations the six v31 metadata columns exist on nodeInfoCache.
    @Test
    func metadataColumnsExistAfterMigration() async throws {
        let db = try AppDatabase.inMemory()
        let columns = try await db.writer.read { db in
            try db.columns(in: "nodeInfoCache").map(\.name)
        }
        for column in [
            "openRegistrations", "usersTotal", "usersActiveMonth",
            "usersActiveHalfyear", "localPosts", "localComments",
        ] {
            #expect(columns.contains(column), "missing v31 column \(column)")
        }
    }

    /// A legacy (pre-v31) nodeInfoCache row survives the v31 ALTER with its
    /// original software fields intact and every new metadata column NULL.
    @Test
    func legacyRowSurvivesWithNilMetadata() async throws {
        // Migrate only up to v30, insert a legacy row, then apply v31.
        let dbQueue = try DatabaseQueue()
        let migrator = AppDatabase.migrator
        try await migrator.migrate(dbQueue, upTo: "v30_nodeInfoCache")
        try await dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO nodeInfoCache (host, softwareName, softwareVersion, fetchedAt)
                    VALUES ('legacy.example', 'lemmy', '0.19.5', '2020-01-01 00:00:00.000')
                    """
            )
        }
        try await migrator.migrate(dbQueue) // apply v31 (and any later)

        // Raw-SQL proof: the row survived and every new column is NULL.
        try await dbQueue.read { db in
            let software = try String.fetchOne(
                db, sql: "SELECT softwareName FROM nodeInfoCache WHERE host = 'legacy.example'"
            )
            #expect(software == "lemmy")
            for column in [
                "openRegistrations", "usersTotal", "usersActiveMonth",
                "usersActiveHalfyear", "localPosts", "localComments",
            ] {
                let nonNull = try Int.fetchOne(
                    db, sql: "SELECT COUNT(*) FROM nodeInfoCache WHERE \(column) IS NOT NULL"
                )
                #expect(nonNull == 0, "expected \(column) to backfill NULL")
            }
        }

        // Record-level proof: the widened NodeInfoCacheRecord decodes the legacy
        // row with all metadata optionals nil.
        let record = try #require(try await dbQueue.read { db in
            try NodeInfoCacheRecord.filter(key: "legacy.example").fetchOne(db)
        })
        #expect(record.softwareVersion == "0.19.5")
        #expect(record.openRegistrations == nil)
        #expect(record.usersTotal == nil)
        #expect(record.usersActiveMonth == nil)
        #expect(record.usersActiveHalfyear == nil)
        #expect(record.localPosts == nil)
        #expect(record.localComments == nil)
    }
}
