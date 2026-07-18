//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import Testing
@testable import SpudDataKit

struct FunStatWritesTests {
    @Test
    func incrementFunStats_insertsNewBuckets() async throws {
        let db = try AppDatabase.inMemory()
        try await db.incrementFunStats([
            FunStatDelta(day: "2026-07-18", hour: 9, key: "tapCount", value: 3),
            FunStatDelta(day: "2026-07-18", hour: 9, key: "scrollDistancePoints", value: 120.5),
        ])
        let rows = try await db.writer.read { db in
            try FunStatRecord.order(Column("key")).fetchAll(db)
        }
        #expect(rows.count == 2)
        #expect(rows[1].key == "tapCount")
        #expect(rows[1].value == 3)
    }

    @Test
    func incrementFunStats_accumulatesIntoExistingBucket() async throws {
        let db = try AppDatabase.inMemory()
        try await db.incrementFunStats([FunStatDelta(day: "2026-07-18", hour: 9, key: "tapCount", value: 3)])
        try await db.incrementFunStats([FunStatDelta(day: "2026-07-18", hour: 9, key: "tapCount", value: 2)])
        let value = try await db.writer.read { db in
            try Double.fetchOne(db, sql: "SELECT value FROM funStat WHERE key = 'tapCount'")
        }
        #expect(value == 5)
    }

    @Test
    func incrementFunStats_separateBucketsPerDayHourKey() async throws {
        let db = try AppDatabase.inMemory()
        try await db.incrementFunStats([
            FunStatDelta(day: "2026-07-18", hour: 9, key: "tapCount", value: 1),
            FunStatDelta(day: "2026-07-18", hour: 10, key: "tapCount", value: 1),
            FunStatDelta(day: "2026-07-19", hour: 9, key: "tapCount", value: 1),
        ])
        let count = try await db.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM funStat") ?? 0
        }
        #expect(count == 3)
    }

    @Test
    func clearFunStats_deletesAllRows() async throws {
        let db = try AppDatabase.inMemory()
        try await db.incrementFunStats([FunStatDelta(day: "2026-07-18", hour: 9, key: "tapCount", value: 1)])
        try await db.clearFunStats()
        let count = try await db.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM funStat") ?? 0
        }
        #expect(count == 0)
    }
}
