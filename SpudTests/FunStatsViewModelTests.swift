//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import Spud
@testable import SpudDataKit

@MainActor
struct FunStatsViewModelTests {
    private final class SpyStatsService: StatsServicing, @unchecked Sendable {
        private(set) var resetCount = 0
        func record(_ key: FunStatKey, amount: Double) async { }
        func setEnabled(_ isEnabled: Bool) async { }
        func flush() async { }
        func resetAllStats() async {
            resetCount += 1
        }

        func appDidBecomeActive() async { }
        func appWillResignActive() async { }
    }

    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    // 2026-07-18 21:35:00 UTC
    //
    // `nonisolated`: this constant is read from inside the `@Sendable`
    // `now:` closure passed to `FunStatsViewModel.init`, which runs off the
    // main actor. A plain `static let` on a `@MainActor struct` would
    // otherwise be actor-isolated and illegal to reference there.
    private nonisolated static let now = Date(timeIntervalSince1970: 1_784_410_500)

    private static func makeViewModel(
        db: AppDatabase,
        spy: SpyStatsService = SpyStatsService()
    ) -> FunStatsViewModel {
        FunStatsViewModel(
            appDatabase: db,
            statsService: spy,
            now: { Self.now },
            calendar: utc,
            locale: Locale(identifier: "en_US")
        )
    }

    @Test
    func heroAndTiles_reflectSeededData() async throws {
        let db = try AppDatabase.inMemory()
        try await db.incrementFunStats([
            // 163 000 pt == 25.4 m
            FunStatDelta(day: "2026-07-18", hour: 21, key: "scrollDistancePoints", value: 163_000),
            FunStatDelta(day: "2026-07-18", hour: 21, key: "postsOpened", value: 1234),
            FunStatDelta(day: "2026-07-18", hour: 21, key: "foregroundSeconds", value: 3900),
        ])
        let viewModel = Self.makeViewModel(db: db)
        viewModel.start()
        // Wait for the first observation emit.
        for _ in 0..<100 where viewModel.summary == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        defer { viewModel.stop() }

        #expect(viewModel.heroDistanceText == "25 m")
        #expect(viewModel.heroEquivalence == nil) // below the smallest landmark
        let postsTile = try #require(viewModel.tiles.first { $0.key == "postsOpened" })
        #expect(postsTile.value == "1.2K")
        let timeTile = try #require(viewModel.tiles.first { $0.key == "timeInApp" })
        #expect(timeTile.value == "1h 5m")
        #expect(viewModel.countingSinceText?.contains("2026") == true)
    }

    @Test
    func resetStats_forwardsToService() async throws {
        let db = try AppDatabase.inMemory()
        let spy = SpyStatsService()
        let viewModel = Self.makeViewModel(db: db, spy: spy)
        await viewModel.resetStats()
        #expect(spy.resetCount == 1)
    }
}
