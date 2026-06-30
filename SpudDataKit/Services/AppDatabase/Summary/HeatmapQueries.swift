//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

extension AppDatabase {
    // MARK: - Public API

    /// Returns a fully populated 18-week contribution heatmap for one metric.
    ///
    /// The window runs from the Monday that is 17 weeks before `asOf`'s Monday
    /// through the Sunday of `asOf`'s own week (126 days inclusive). Each cell
    /// in the returned grid is midnight UTC of its calendar day.
    ///
    /// - Parameters:
    ///   - accountId: Row ID of the account whose activity to query.
    ///   - personRowId: Row ID in the `person` table for the signed-in user.
    ///     Required for the `.all` metric to include authored-post activity;
    ///     ignored for `.reads` and `.votes`.
    ///   - metric: Which activity dimension to aggregate.
    ///   - asOf: Reference date that anchors the 18-week window. Production
    ///     callers pass `Date()`; tests pass a fixed value.
    public func heatmapSeries(
        accountId: Int64,
        personRowId: Int64?,
        metric: HeatmapMetric,
        asOf: Date
    ) throws -> HeatmapSeries {
        try writer.read { db in
            let cal = Self.utcMondayCal
            let (windowStart, weekStart) = Self.heatmapWindow(asOf: asOf, cal: cal)
            let windowEnd = cal.date(byAdding: .day, value: 6, to: weekStart)!
            let startStr = utcDayString(windowStart, cal: cal)
            let endStr = utcDayString(windowEnd, cal: cal)

            var counts: [String: Int] = [:]

            // --- reads ---
            if metric == .reads || metric == .all {
                let rows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT date(lastOpenedAt) AS day, COUNT(*) AS cnt
                        FROM postInteraction
                        WHERE accountId = :accountId
                          AND lastOpenedAt IS NOT NULL
                          AND date(lastOpenedAt) >= :start
                          AND date(lastOpenedAt) <= :end
                        GROUP BY day
                        """,
                    arguments: ["accountId": accountId, "start": startStr, "end": endStr]
                )
                for row in rows {
                    let day: String = row["day"]
                    let cnt: Int = row["cnt"]
                    counts[day, default: 0] += cnt
                }
            }

            // --- votes ---
            if metric == .votes || metric == .all {
                let rows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT strftime('%Y-%m-%d', datetime(votedAt, 'unixepoch')) AS day,
                               COUNT(*) AS cnt
                        FROM voteEvent
                        WHERE accountId = :accountId
                          AND strftime('%Y-%m-%d', datetime(votedAt, 'unixepoch')) >= :start
                          AND strftime('%Y-%m-%d', datetime(votedAt, 'unixepoch')) <= :end
                        GROUP BY day
                        """,
                    arguments: ["accountId": accountId, "start": startStr, "end": endStr]
                )
                for row in rows {
                    let day: String = row["day"]
                    let cnt: Int = row["cnt"]
                    counts[day, default: 0] += cnt
                }
            }

            // --- authored posts (all metric only) ---
            if metric == .all, let personRowId {
                let rows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT date(published) AS day, COUNT(*) AS cnt
                        FROM post
                        WHERE accountId = :accountId
                          AND creatorId = :personRowId
                          AND date(published) >= :start
                          AND date(published) <= :end
                        GROUP BY day
                        """,
                    arguments: [
                        "accountId": accountId,
                        "personRowId": personRowId,
                        "start": startStr,
                        "end": endStr,
                    ]
                )
                for row in rows {
                    let day: String = row["day"]
                    let cnt: Int = row["cnt"]
                    counts[day, default: 0] += cnt
                }
            }

            // --- build 18 x 7 grid ---
            var weeks: [[HeatmapDay]] = []
            var total = 0

            for weekOffset in 0..<18 {
                let weekMon = cal.date(byAdding: .weekOfYear, value: weekOffset, to: windowStart)!
                var week: [HeatmapDay] = []
                for dayOffset in 0..<7 {
                    let dayDate = cal.date(byAdding: .day, value: dayOffset, to: weekMon)!
                    let dayStr = utcDayString(dayDate, cal: cal)
                    let cnt = counts[dayStr] ?? 0
                    total += cnt
                    week.append(HeatmapDay(date: dayDate, bucket: Self.bucket(for: cnt), count: cnt))
                }
                weeks.append(week)
            }

            return HeatmapSeries(metric: metric, total: total, weeks: weeks)
        }
    }

    /// Returns activity-based extras for the account: streak, top community, and
    /// busiest time-of-day band.
    ///
    /// - Parameters:
    ///   - accountId: Row ID of the account.
    ///   - personRowId: Row ID in the `person` table; when provided, authored posts
    ///     contribute to `topCommunity`.
    ///   - asOf: Reference date used to anchor the streak walk. Never call
    ///     `Date()` inside this function; callers inject the value.
    public func summaryExtras(
        accountId: Int64,
        personRowId: Int64?,
        asOf: Date
    ) throws -> SummaryExtras {
        try writer.read { db in
            let cal = Self.utcMondayCal

            // --- streak ---
            // Union all activity days (reads + votes) into a Set<String>.
            var activityDays: Set<String> = []

            let readDayRows = try String.fetchAll(db, sql: """
                SELECT DISTINCT date(lastOpenedAt)
                FROM postInteraction
                WHERE accountId = ? AND lastOpenedAt IS NOT NULL
                """, arguments: [accountId])
            activityDays.formUnion(readDayRows)

            let voteDayRows = try String.fetchAll(db, sql: """
                SELECT DISTINCT strftime('%Y-%m-%d', datetime(votedAt, 'unixepoch'))
                FROM voteEvent
                WHERE accountId = ?
                """, arguments: [accountId])
            activityDays.formUnion(voteDayRows)

            // Walk backward from asOf's UTC day.
            let asOfDayStr = utcDayString(asOf, cal: cal)
            var streak = 0
            if activityDays.contains(asOfDayStr) {
                streak = 1
                var cursor = cal.date(byAdding: .day, value: -1, to: asOf)!
                while activityDays.contains(utcDayString(cursor, cal: cal)) {
                    streak += 1
                    cursor = cal.date(byAdding: .day, value: -1, to: cursor)!
                }
            }

            // --- topCommunity ---
            // Accumulate per-community counts from vote events and authored posts.
            var communityCounts: [String: Int] = [:]

            let voteCommRows = try Row.fetchAll(db, sql: """
                SELECT communityName AS name, COUNT(*) AS cnt
                FROM voteEvent
                WHERE accountId = ? AND communityName IS NOT NULL
                GROUP BY communityName
                """, arguments: [accountId])
            for row in voteCommRows {
                let name: String = row["name"]
                let cnt: Int = row["cnt"]
                communityCounts[name, default: 0] += cnt
            }

            if let personRowId {
                let postCommRows = try Row.fetchAll(db, sql: """
                    SELECT c.name AS name, COUNT(*) AS cnt
                    FROM post p
                    JOIN community c ON p.communityId = c.id
                    WHERE p.accountId = ? AND p.creatorId = ?
                    GROUP BY c.name
                    """, arguments: [accountId, personRowId])
                for row in postCommRows {
                    let name: String = row["name"]
                    let cnt: Int = row["cnt"]
                    communityCounts[name, default: 0] += cnt
                }
            }

            // Highest count wins; alphabetical name breaks ties.
            let topCommunity: String? = communityCounts
                .sorted { lhs, rhs in
                    lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key
                }
                .first?.key

            // --- busiest time-of-day band ---
            // Band indices: 0=Mornings(5-11), 1=Afternoons(12-17),
            //               2=Evenings(18-22), 3=Nights(0-4,23).
            // Lowest index wins ties.
            var bandCounts = [Int](repeating: 0, count: 4)

            let readHours = try Int.fetchAll(db, sql: """
                SELECT CAST(strftime('%H', lastOpenedAt) AS INTEGER)
                FROM postInteraction
                WHERE accountId = ? AND lastOpenedAt IS NOT NULL
                """, arguments: [accountId])
            for h in readHours {
                bandCounts[Self.timeBandIndex(hour: h)] += 1
            }

            let voteHours = try Int.fetchAll(db, sql: """
                SELECT CAST(strftime('%H', datetime(votedAt, 'unixepoch')) AS INTEGER)
                FROM voteEvent
                WHERE accountId = ?
                """, arguments: [accountId])
            for h in voteHours {
                bandCounts[Self.timeBandIndex(hour: h)] += 1
            }

            let totalActivity = bandCounts.reduce(0, +)
            let busiest: String?
            if totalActivity == 0 {
                busiest = nil
            } else {
                let maxCount = bandCounts.max()!
                // firstIndex(of:) returns the lowest-index band when counts tie.
                let bandIdx = bandCounts.firstIndex(of: maxCount)!
                busiest = Self.timeBandName(index: bandIdx)
            }

            return SummaryExtras(
                streakDays: streak,
                topCommunity: topCommunity,
                busiest: busiest
            )
        }
    }

    // MARK: - Private helpers

    /// UTC Gregorian calendar with Monday as the first weekday.
    private static let utcMondayCal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2 // Monday
        return c
    }()

    /// Computes the 18-week window anchored at `asOf`.
    ///
    /// Returns:
    ///   - `windowStart`: UTC midnight of the Monday that is 17 weeks before
    ///     the Monday of `asOf`'s week.
    ///   - `weekStart`: UTC midnight of the Monday of `asOf`'s week.
    private static func heatmapWindow(asOf: Date, cal: Calendar) -> (windowStart: Date, weekStart: Date) {
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: asOf)
        let weekStart = cal.date(from: comps)!
        let windowStart = cal.date(byAdding: .weekOfYear, value: -17, to: weekStart)!
        return (windowStart, weekStart)
    }

    /// Maps a raw activity count to a 0–4 bucket.
    ///
    /// | bucket | count     |
    /// |--------|-----------|
    /// | 0      | 0         |
    /// | 1      | 1–2       |
    /// | 2      | 3–5       |
    /// | 3      | 6–9       |
    /// | 4      | 10+       |
    private static func bucket(for count: Int) -> Int {
        switch count {
        case 0: return 0
        case 1...2: return 1
        case 3...5: return 2
        case 6...9: return 3
        default: return 4
        }
    }

    /// Maps a UTC hour (0–23) to a time-band index.
    ///
    /// | index | band       | hours       |
    /// |-------|------------|-------------|
    /// | 0     | Mornings   | 5–11        |
    /// | 1     | Afternoons | 12–17       |
    /// | 2     | Evenings   | 18–22       |
    /// | 3     | Nights     | 0–4 and 23  |
    private static func timeBandIndex(hour: Int) -> Int {
        switch hour {
        case 5...11: return 0
        case 12...17: return 1
        case 18...22: return 2
        default: return 3
        }
    }

    private static func timeBandName(index: Int) -> String {
        switch index {
        case 0: return "Mornings"
        case 1: return "Afternoons"
        case 2: return "Evenings"
        default: return "Nights"
        }
    }
}

// MARK: - File-private utilities

/// Formats `date` as "YYYY-MM-DD" in UTC, matching SQLite's `date()` output format.
private func utcDayString(_ date: Date, cal: Calendar) -> String {
    let comps = cal.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", comps.year!, comps.month!, comps.day!)
}
