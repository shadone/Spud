//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

public extension AppDatabase {
    /// One-shot assembly of the Fun Stats read-model. `now` drives "today"
    /// for the current-streak grace rule; injectable for tests.
    func funStatsSummarySync(calendar: Calendar, now: () -> Date) throws -> FunStatsSummary {
        try writer.read { db in
            try Self.funStatsSummary(db: db, calendar: calendar, today: now())
        }
    }

    /// Shared by the sync read and the ValueObservation so both derive the
    /// summary identically.
    static func funStatsSummary(db: Database, calendar: Calendar, today: Date) throws -> FunStatsSummary {
        var totals: [FunStatKey: Double] = [:]
        let totalRows = try Row.fetchAll(db, sql: "SELECT key, sum(value) AS total FROM funStat GROUP BY key")
        for row in totalRows {
            guard let key = FunStatKey(rawValue: row["key"]) else { continue }
            totals[key] = row["total"]
        }

        let firstDay = try String.fetchOne(db, sql: "SELECT min(day) FROM funStat")
        let activeDays = try String.fetchAll(db, sql: "SELECT DISTINCT day FROM funStat ORDER BY day")

        // Magnitude-type counters — durations and distances — are excluded so
        // they don't drown event counts in the rhythm histogram.
        let mostActiveHour = try Int.fetchOne(
            db,
            sql: """
                SELECT hour FROM funStat WHERE key NOT IN (?, ?)
                GROUP BY hour ORDER BY sum(value) DESC, hour ASC LIMIT 1
                """,
            arguments: [FunStatKey.foregroundSeconds.rawValue, FunStatKey.scrollDistancePoints.rawValue]
        )

        let todayBucket = FunStatBucket.make(date: today, calendar: calendar)
        let streaks = FunStatStreaks.compute(activeDays: activeDays, today: todayBucket.day)

        return FunStatsSummary(
            totals: totals,
            firstDay: firstDay,
            currentStreakDays: streaks.current,
            longestStreakDays: streaks.longest,
            mostActiveHour: mostActiveHour
        )
    }
}
