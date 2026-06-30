//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Observation
import SpudDataKit

/// View model driving the Summary dashboard screen.
///
/// `asOf` is injected so snapshot tests can pin the date and produce
/// deterministic output. Production callers use the default `Date()`.
@Observable
@MainActor
final class SummaryViewModel {
    // MARK: Observable state

    private(set) var stats: SummaryStats?
    private(set) var series: HeatmapSeries
    private(set) var extras: SummaryExtras
    var selectedMetric: HeatmapMetric = .all

    // MARK: Private

    private let appDatabase: AppDatabase
    private let accountId: Int64
    private let personRowId: Int64?
    let asOf: Date

    // `@ObservationIgnored` keeps these off the @Observable tracking
    // machinery so the nonisolated `deinit` can cancel them safely.
    @ObservationIgnored private var statsStreamTask: Task<Void, Never>?

    // MARK: Init

    init(
        appDatabase: AppDatabase,
        accountId: Int64,
        personRowId: Int64?,
        asOf: Date = Date()
    ) {
        self.appDatabase = appDatabase
        self.accountId = accountId
        self.personRowId = personRowId
        self.asOf = asOf

        // Synchronous initial data — fills the first render without an async hop.
        series = (try? appDatabase.heatmapSeries(
            accountId: accountId,
            personRowId: personRowId,
            metric: .all,
            asOf: asOf
        )) ?? HeatmapSeries(metric: .all, total: 0, weeks: Self.emptyWeeks(asOf: asOf))

        extras = (try? appDatabase.summaryExtras(
            accountId: accountId,
            personRowId: personRowId,
            asOf: asOf
        )) ?? SummaryExtras(streakDays: 0, topCommunity: nil, busiest: nil)
    }

    deinit {
        statsStreamTask?.cancel()
    }

    // MARK: Lifecycle

    func start() {
        let stream = appDatabase.observeSummaryStats(
            accountId: accountId,
            personRowId: personRowId ?? 0
        )
        statsStreamTask?.cancel()
        statsStreamTask = Task { [weak self] in
            for await newStats in stream {
                if Task.isCancelled { break }
                self?.stats = newStats
            }
        }
    }

    func stop() {
        statsStreamTask?.cancel()
    }

    // MARK: Metric switching

    /// Switches the heatmap to `metric` and refreshes `series` and `extras`
    /// synchronously (GRDB reads are fast; no async hop needed).
    func selectMetric(_ metric: HeatmapMetric) {
        guard metric != selectedMetric else { return }
        selectedMetric = metric
        reloadSeries()
    }

    // MARK: Private helpers

    private func reloadSeries() {
        series = (try? appDatabase.heatmapSeries(
            accountId: accountId,
            personRowId: personRowId,
            metric: selectedMetric,
            asOf: asOf
        )) ?? HeatmapSeries(metric: selectedMetric, total: 0, weeks: Self.emptyWeeks(asOf: asOf))

        extras = (try? appDatabase.summaryExtras(
            accountId: accountId,
            personRowId: personRowId,
            asOf: asOf
        )) ?? SummaryExtras(streakDays: 0, topCommunity: nil, busiest: nil)
    }

    /// Builds a blank 18×7 grid anchored to `asOf`, matching the structure
    /// that `heatmapSeries` would return when the DB has no data.
    private static func emptyWeeks(asOf: Date) -> [[HeatmapDay]] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.firstWeekday = 2
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: asOf)
        let weekStart = cal.date(from: comps)!
        let windowStart = cal.date(byAdding: .weekOfYear, value: -17, to: weekStart)!
        var weeks: [[HeatmapDay]] = []
        for weekOffset in 0..<18 {
            let mon = cal.date(byAdding: .weekOfYear, value: weekOffset, to: windowStart)!
            var week: [HeatmapDay] = []
            for dayOffset in 0..<7 {
                let day = cal.date(byAdding: .day, value: dayOffset, to: mon)!
                week.append(HeatmapDay(date: day, bucket: 0, count: 0))
            }
            weeks.append(week)
        }
        return weeks
    }
}
