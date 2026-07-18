//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Observation
import SpudDataKit
import SpudUtilKit

/// Drives the Fun Stats screen from the live `FunStatsSummary` observation.
@MainActor
@Observable
final class FunStatsViewModel {
    private let appDatabase: AppDatabase
    private let statsService: StatsServicing
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    private let locale: Locale

    /// `@ObservationIgnored` keeps this off the @Observable tracking
    /// machinery so the nonisolated `deinit` can cancel it safely.
    @ObservationIgnored private var observationTask: Task<Void, Never>?

    private(set) var summary: FunStatsSummary?

    init(
        appDatabase: AppDatabase,
        statsService: StatsServicing,
        now: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .current
    ) {
        self.appDatabase = appDatabase
        self.statsService = statsService
        self.now = now
        self.calendar = calendar
        self.locale = locale
    }

    deinit {
        observationTask?.cancel()
    }

    /// Starts (or restarts) the live `FunStatsSummary` observation. Call from
    /// `onAppear`; idempotent against a previously-running observation.
    func start() {
        observationTask?.cancel()
        let stream = appDatabase.observeFunStatsSummary(calendar: calendar, now: now)
        observationTask = Task { @MainActor [weak self] in
            for await summary in stream {
                guard let self, !Task.isCancelled else { break }
                self.summary = summary
            }
        }
    }

    /// Cancels the live observation. Call from `onDisappear`.
    func stop() {
        observationTask?.cancel()
        observationTask = nil
    }

    /// Deletes every persisted fun-stat counter. Backs the "Reset Stats"
    /// confirmation action; the next observation emit reflects the empty state.
    func resetStats() async {
        await statsService.resetAllStats()
    }

    // MARK: - Presentation

    /// The hero distance string ("25 m" / "12.3 km"), derived from the
    /// lifetime scroll-distance total.
    var heroDistanceText: String {
        let meters = ScrollDistance.meters(fromPoints: summary?.total(.scrollDistancePoints) ?? 0)
        return ScrollDistance.displayString(meters: meters, locale: locale)
    }

    /// A real-world landmark comparison for the hero distance, or nil below
    /// the smallest landmark.
    var heroEquivalence: String? {
        let meters = ScrollDistance.meters(fromPoints: summary?.total(.scrollDistancePoints) ?? 0)
        return FunEquivalence.phrase(forMeters: meters)
    }

    /// The 8 headline stat tiles, in display order.
    var tiles: [SummaryStat] {
        let summary = summary ?? .empty
        return [
            SummaryStat(
                key: "postsOpened",
                label: "Posts read",
                value: CountFormatter.string(Int64(summary.total(.postsOpened))),
                icon: "book",
                source: .forward
            ),
            SummaryStat(
                key: "postsSeen",
                label: "Posts seen",
                value: CountFormatter.string(Int64(summary.total(.postsSeen))),
                icon: "eye",
                source: .forward
            ),
            SummaryStat(
                key: "taps",
                label: "Taps",
                value: CountFormatter.string(Int64(summary.total(.tapCount))),
                icon: "hand.tap",
                source: .forward
            ),
            SummaryStat(
                key: "votes",
                label: "Votes cast",
                value: CountFormatter.string(Int64(summary.total(.votesCast))),
                icon: "arrow.up.arrow.down",
                source: .forward
            ),
            SummaryStat(
                key: "sessions",
                label: "Sessions",
                value: CountFormatter.string(Int64(summary.total(.sessionCount))),
                icon: "door.left.hand.open",
                source: .forward
            ),
            SummaryStat(
                key: "timeInApp",
                label: "Time in app",
                value: Self.durationText(seconds: summary.total(.foregroundSeconds)),
                icon: "clock",
                source: .forward
            ),
            SummaryStat(
                key: "streak",
                label: "Longest streak",
                value: summary.longestStreakDays == 1 ? "1 day" : "\(summary.longestStreakDays) days",
                icon: "flame",
                source: .forward
            ),
            SummaryStat(
                key: "activeHour",
                label: "Most active hour",
                value: hourText(summary.mostActiveHour),
                icon: hourIcon(summary.mostActiveHour),
                source: .forward
            ),
        ]
    }

    /// The long-tail counters, shown as plain label/value rows below the tiles.
    var moreRows: [(label: String, value: String)] {
        let summary = summary ?? .empty
        return [
            ("Pull-to-refreshes", CountFormatter.string(Int64(summary.total(.pullToRefreshCount)))),
            ("Images viewed", CountFormatter.string(Int64(summary.total(.imagesViewed)))),
            ("Links opened", CountFormatter.string(Int64(summary.total(.linksOpened)))),
            ("Comments written", CountFormatter.string(Int64(summary.total(.commentsPosted)))),
            ("Posts written", CountFormatter.string(Int64(summary.total(.postsPosted)))),
            ("Searches", CountFormatter.string(Int64(summary.total(.searchesRun)))),
        ]
    }

    /// "Counting since <date>" footer text, nil when no data has been
    /// recorded yet (the view falls back to "Counting starts today").
    var countingSinceText: String? {
        guard let firstDay = summary?.firstDay else { return nil }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = calendar.timeZone
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: firstDay) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return "Counting since \(formatter.string(from: date))"
    }

    private static func durationText(seconds: Double) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    /// Localized hour-of-day text (e.g. "9 PM") for the "Most active hour" tile.
    private func hourText(_ hour: Int?) -> String {
        guard let hour else { return "-" }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("j")
        var components = DateComponents()
        components.hour = hour
        let date = calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
        return formatter.string(from: date)
    }

    /// Night-owl flavor: a moon for late-night/early-morning hours, sun otherwise.
    private func hourIcon(_ hour: Int?) -> String {
        guard let hour else { return "clock" }
        return (hour >= 21 || hour < 6) ? "moon.stars" : "sun.max"
    }
}

private extension FunStatsSummary {
    static let empty = FunStatsSummary(
        totals: [:],
        firstDay: nil,
        currentStreakDays: 0,
        longestStreakDays: 0,
        mostActiveHour: nil
    )
}
