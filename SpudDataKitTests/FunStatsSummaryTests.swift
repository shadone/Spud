import Foundation
import GRDB
import Testing
@testable import SpudDataKit

struct FunStatsSummaryTests {
    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// 2026-07-18 21:35:00 UTC (same constant as FunStatBucketTests)
    private static let now = Date(timeIntervalSince1970: 1_784_410_500)

    @Test
    func emptyDatabase_yieldsZeroSummary() throws {
        let db = try AppDatabase.inMemory()
        let summary = try db.funStatsSummarySync(calendar: Self.utc, now: { Self.now })
        #expect(summary.total(.tapCount) == 0)
        #expect(summary.firstDay == nil)
        #expect(summary.currentStreakDays == 0)
        #expect(summary.longestStreakDays == 0)
        #expect(summary.mostActiveHour == nil)
    }

    @Test
    func totals_sumAcrossBuckets() async throws {
        let db = try AppDatabase.inMemory()
        try await db.incrementFunStats([
            FunStatDelta(day: "2026-07-17", hour: 9, key: "tapCount", value: 3),
            FunStatDelta(day: "2026-07-18", hour: 21, key: "tapCount", value: 4),
            FunStatDelta(day: "2026-07-18", hour: 21, key: "scrollDistancePoints", value: 500),
        ])
        let summary = try db.funStatsSummarySync(calendar: Self.utc, now: { Self.now })
        #expect(summary.total(.tapCount) == 7)
        #expect(summary.total(.scrollDistancePoints) == 500)
        #expect(summary.firstDay == "2026-07-17")
        #expect(summary.currentStreakDays == 2)
    }

    @Test
    func mostActiveHour_isHourWithLargestEventSum() async throws {
        let db = try AppDatabase.inMemory()
        try await db.incrementFunStats([
            FunStatDelta(day: "2026-07-18", hour: 9, key: "tapCount", value: 10),
            FunStatDelta(day: "2026-07-18", hour: 21, key: "tapCount", value: 5),
            FunStatDelta(day: "2026-07-17", hour: 21, key: "tapCount", value: 6),
        ])
        let summary = try db.funStatsSummarySync(calendar: Self.utc, now: { Self.now })
        #expect(summary.mostActiveHour == 21) // 11 total beats 10
    }

    @Test
    func mostActiveHour_ignoresForegroundSeconds() async throws {
        // foregroundSeconds values dwarf event counts; they must not skew
        // the "most active hour" histogram.
        let db = try AppDatabase.inMemory()
        try await db.incrementFunStats([
            FunStatDelta(day: "2026-07-18", hour: 3, key: "foregroundSeconds", value: 90000),
            FunStatDelta(day: "2026-07-18", hour: 21, key: "tapCount", value: 1),
        ])
        let summary = try db.funStatsSummarySync(calendar: Self.utc, now: { Self.now })
        #expect(summary.mostActiveHour == 21)
    }

    @Test
    func mostActiveHour_ignoresScrollDistance() async throws {
        // scrollDistancePoints values (thousands per active minute) dwarf
        // event counts just like foregroundSeconds; they must not skew the
        // "most active hour" histogram either.
        let db = try AppDatabase.inMemory()
        try await db.incrementFunStats([
            FunStatDelta(day: "2026-07-18", hour: 3, key: "scrollDistancePoints", value: 90000),
            FunStatDelta(day: "2026-07-18", hour: 21, key: "tapCount", value: 1),
        ])
        let summary = try db.funStatsSummarySync(calendar: Self.utc, now: { Self.now })
        #expect(summary.mostActiveHour == 21)
    }

    @Test
    func mostActiveHour_tieBrokenByEarliestHour() async throws {
        let db = try AppDatabase.inMemory()
        try await db.incrementFunStats([
            FunStatDelta(day: "2026-07-18", hour: 21, key: "tapCount", value: 7),
            FunStatDelta(day: "2026-07-18", hour: 9, key: "tapCount", value: 7),
        ])
        let summary = try db.funStatsSummarySync(calendar: Self.utc, now: { Self.now })
        #expect(summary.mostActiveHour == 9)
    }

    @Test
    func observeFunStatsSummary_emitsOnChange() async throws {
        let db = try AppDatabase.inMemory()
        var iterator = db.observeFunStatsSummary(calendar: Self.utc, now: { Self.now }).makeAsyncIterator()
        let initial = await iterator.next()
        #expect(initial?.total(.tapCount) == 0)

        try await db.incrementFunStats([
            FunStatDelta(day: "2026-07-18", hour: 21, key: "tapCount", value: 4),
        ])
        let updated = await iterator.next()
        #expect(updated?.total(.tapCount) == 4)
    }
}
