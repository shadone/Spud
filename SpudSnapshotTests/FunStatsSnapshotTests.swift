//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import SpudDataKit
import SpudUIKit
import SwiftUI
import UIKit
import XCTest
@testable import Spud

/// Screen snapshots of the Fun Stats screen (`FunStatsView`) in its empty and
/// populated states, light and dark.
///
/// ## Async GRDB observation
///
/// `FunStatsViewModel.start()` fires the async `observeFunStatsSummary`
/// stream (mirrors `DiagnosticLogSnapshotTests` / `SummarySnapshotTests`). We
/// must suspend the main actor (`Task.sleep` / `Task.yield`) between polls so
/// the observation continuation can land — a synchronous busy-spin would
/// starve it and record a blank screen. We poll `viewModel.summary` directly
/// (not the rendered view hierarchy), since SwiftUI may not have run its
/// layout pass yet on an off-screen `UIHostingController`.
@MainActor
final class FunStatsSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Fun Stats tiles/hero icon use `Color.accentColor` — pin the
        // process-wide accent so renders don't depend on the sim's persisted
        // accent preference. See `SnapshotDeterminism.pinAccent()`.
        SnapshotDeterminism.pinAccent()
        // Pin the host scene's status bar hidden so nav-hosted captures are
        // immune to the sim's persisted orientation state (the 44pt-shift
        // regression). See `SnapshotDeterminism.pinStatusBarHidden()`.
        SnapshotDeterminism.pinStatusBarHidden()
    }

    /// 2026-07-18 21:35:00 UTC — matches `FunStatsViewModelTests` so the fixed
    /// "now" used here reads the same way as the covering unit test.
    private static let now = Date(timeIntervalSince1970: 1_784_410_500)

    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// A no-op `StatsServicing` double — the screen only reads the DB
    /// observation, it never records through the service.
    private struct NoopStatsService: StatsServicing {
        func record(_ key: FunStatKey, amount: Double) async { }
        func setEnabled(_ isEnabled: Bool) async { }
        func flush() async { }
        func resetAllStats() async { }
        func appDidBecomeActive() async { }
        func appWillResignActive() async { }
    }

    /// Tall enough to show the hero card, the full 2-column/8-tile grid, all
    /// 6 more-numbers rows, and the footer without scrolling.
    private let snapshotSize = CGSize(width: 390, height: 1300)

    private func makeScreen(db: AppDatabase) -> (host: UIHostingController<AnyView>, viewModel: FunStatsViewModel) {
        let viewModel = FunStatsViewModel(
            appDatabase: db,
            statsService: NoopStatsService(),
            now: { Self.now },
            calendar: Self.utc,
            locale: Locale(identifier: "en_US")
        )
        let view = AnyView(NavigationStack { FunStatsView(viewModel: viewModel) })
        let host = UIHostingController(rootView: view)
        // `FunStatsView`'s icons/hero read the plain `Color.accentColor`
        // (SwiftUI bridges that from the enclosing UIKit `tintColor`
        // cascade). In the live app that cascade comes from the app
        // window's tint (set process-wide by `SnapshotDeterminism.pinAccent()`
        // via `ThemeManager`), but `.image(on: .deterministicPhone)` renders
        // fully off-screen in the snapshot library's own private window, so
        // it never sees that cascade. Set the tint directly on the hosted
        // view so the off-screen render still matches the live app's brand
        // teal instead of falling back to system blue.
        host.view.tintColor = ThemeManager.currentAccentColor
        return (host, viewModel)
    }

    /// Waits for the screen's first GRDB observation emit (polling the view
    /// model directly, not SwiftUI's private view tree), then lets SwiftUI
    /// commit a layout pass so the snapshot is not a blank pre-data frame.
    private func waitForFirstEmit(
        _ viewModel: FunStatsViewModel,
        in host: UIViewController,
        line: UInt = #line
    ) async {
        // .onAppear may not fire for an off-screen host; start() is
        // idempotent, so drive it explicitly.
        viewModel.start()
        let deadline = Date().addingTimeInterval(4)
        while viewModel.summary == nil, Date() < deadline {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000)
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
        }
        guard viewModel.summary != nil else {
            XCTFail(
                "FunStatsViewModel never emitted a summary — refusing to snapshot a blank screen.",
                line: line
            )
            return
        }
        // Brief settle for SwiftUI's layout pass to fully commit.
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try? await Task.sleep(nanoseconds: 100_000_000)
        host.view.layoutIfNeeded()
    }

    // MARK: - Empty state

    func test_empty() async throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let db = try AppDatabase.inMemory()
            let (host, viewModel) = makeScreen(db: db)
            host.view.frame = CGRect(origin: .zero, size: snapshotSize)
            await waitForFirstEmit(viewModel, in: host)

            assertSnapshot(
                matching: host,
                as: .image(
                    on: .deterministicPhone,
                    size: snapshotSize,
                    traits: UITraitCollection(userInterfaceStyle: style)
                ),
                named: style == .dark ? "dark" : "light"
            )
        }
    }

    // MARK: - Populated state

    func test_populated() async throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let db = try AppDatabase.inMemory()
            try await db.incrementFunStats([
                FunStatDelta(day: "2026-07-01", hour: 9, key: "scrollDistancePoints", value: 14_000_000),
                FunStatDelta(day: "2026-07-17", hour: 21, key: "scrollDistancePoints", value: 2_000_000),
                FunStatDelta(day: "2026-07-18", hour: 21, key: "postsOpened", value: 1234),
                FunStatDelta(day: "2026-07-18", hour: 21, key: "postsSeen", value: 8765),
                FunStatDelta(day: "2026-07-18", hour: 21, key: "tapCount", value: 45678),
                FunStatDelta(day: "2026-07-18", hour: 21, key: "votesCast", value: 321),
                FunStatDelta(day: "2026-07-18", hour: 21, key: "sessionCount", value: 89),
                FunStatDelta(day: "2026-07-18", hour: 21, key: "foregroundSeconds", value: 123_456),
                FunStatDelta(day: "2026-07-18", hour: 21, key: "pullToRefreshCount", value: 77),
                FunStatDelta(day: "2026-07-18", hour: 21, key: "imagesViewed", value: 456),
                FunStatDelta(day: "2026-07-18", hour: 21, key: "linksOpened", value: 123),
                FunStatDelta(day: "2026-07-18", hour: 21, key: "commentsPosted", value: 42),
                FunStatDelta(day: "2026-07-18", hour: 21, key: "postsPosted", value: 7),
                FunStatDelta(day: "2026-07-18", hour: 21, key: "searchesRun", value: 55),
            ])

            let (host, viewModel) = makeScreen(db: db)
            host.view.frame = CGRect(origin: .zero, size: snapshotSize)
            await waitForFirstEmit(viewModel, in: host)

            assertSnapshot(
                matching: host,
                as: .image(
                    on: .deterministicPhone,
                    size: snapshotSize,
                    traits: UITraitCollection(userInterfaceStyle: style)
                ),
                named: style == .dark ? "dark" : "light"
            )
        }
    }
}
