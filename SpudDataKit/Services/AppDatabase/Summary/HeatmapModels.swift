//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// The activity dimension shown in the contribution heatmap.
///
/// - `all`: union of reads + votes + authored posts (per-day SUM).
/// - `reads`: posts the account has opened (`postInteraction.lastOpenedAt`).
/// - `votes`: votes cast by the account (`voteEvent` rows, forward-only).
public enum HeatmapMetric: String, Sendable, CaseIterable {
    case all
    case reads
    case votes
}

/// A single day cell in the contribution heatmap.
///
/// `date` is the UTC midnight of the day (suitable for display via a
/// date formatter with UTC timezone). `count` is the raw activity count for
/// that day; `bucket` is a 0–4 intensity tier used for color mapping:
///
/// | bucket | count      |
/// |--------|------------|
/// | 0      | 0          |
/// | 1      | 1–2        |
/// | 2      | 3–5        |
/// | 3      | 6–9        |
/// | 4      | 10 or more |
public struct HeatmapDay: Sendable, Equatable {
    public let date: Date
    /// Activity intensity tier, 0 (none) through 4 (highest).
    public let bucket: Int
    /// Raw activity count for the day.
    public let count: Int

    public init(date: Date, bucket: Int, count: Int) {
        self.date = date
        self.bucket = bucket
        self.count = count
    }
}

/// A complete 18-week heatmap grid for one metric.
///
/// `weeks` is ordered oldest-first: `weeks[0]` is the earliest week and
/// `weeks[17]` is the week containing `asOf`. Within each week array the
/// seven elements are Monday-indexed: index 0 = Monday, index 6 = Sunday.
/// All days in the window are always present (missing days have `count == 0`
/// and `bucket == 0`).
///
/// `total` is the sum of all day counts within the 18-week window.
public struct HeatmapSeries: Sendable, Equatable {
    public let metric: HeatmapMetric
    /// Sum of all day counts in the 18-week window.
    public let total: Int
    /// 18 weeks x 7 days, oldest-first, Monday-indexed within each week.
    public let weeks: [[HeatmapDay]]

    public init(metric: HeatmapMetric, total: Int, weeks: [[HeatmapDay]]) {
        self.metric = metric
        self.total = total
        self.weeks = weeks
    }
}

/// Extra summary insights shown alongside the heatmap.
///
/// - `streakDays`: current run of consecutive calendar days with any
///   activity (reads, votes, or authored posts) ending at or before `asOf`.
///   Zero means no activity on `asOf`'s calendar day.
/// - `topCommunity`: display name of the community in which the account has
///   been most active (votes + authored posts). Nil when there is no data.
/// - `busiest`: the modal activity time-of-day band phrased as a single
///   English word or phrase: "Mornings", "Afternoons", "Evenings", or
///   "Nights". Nil when there is no activity data.
public struct SummaryExtras: Sendable, Equatable {
    public let streakDays: Int
    public let topCommunity: String?
    public let busiest: String?

    public init(streakDays: Int, topCommunity: String?, busiest: String?) {
        self.streakDays = streakDays
        self.topCommunity = topCommunity
        self.busiest = busiest
    }
}
