//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import SpudDataKit
import UIKit
import XCTest
@testable import Spud

/// Deterministic full-screen snapshots of `SummaryViewController` and the
/// `SummaryHeatmapCardView` component.
///
/// ## Determinism strategy
///
/// All tests inject a fixed `asOf = 2025-03-24T00:00:00Z` (a Monday) so the
/// 18-week heatmap window is the same on every run. DB is seeded with fixed
/// timestamps; no wall-clock values appear in the rendered output.
///
/// ## Async GRDB observation
///
/// `SummaryViewModel.start()` fires the async `observeSummaryStats` stream.
/// Tests must suspend the main actor (`Task.sleep` / `Task.yield`) so the
/// observation continuation can land and configure the identity strip + tiles.
/// We poll for a sentinel label rather than sleeping a fixed duration so the
/// test fails loudly (not silently records a blank) if the observation never
/// fires.
///
/// ## Snapshot size
///
/// `.image(on: .iPhone13Pro, size:, traits:)` is device-independent (the
/// `size:` override fixes pixel dimensions). The full-dashboard size is tall
/// enough to hold all four card sections without scrolling.
@MainActor
final class SummarySnapshotTests: XCTestCase {
    // MARK: - Fake dependencies

    private struct SnapshotDependencies: HasAppDatabase {
        let appDatabase: AppDatabase
    }

    // MARK: - Constants

    /// 2025-03-24T00:00:00Z (Monday) — anchors the 18-week heatmap window.
    private let fixedAsOf = Date(timeIntervalSince1970: 1_742_774_400)

    /// Portrait iPhone 13 Pro dimensions — tall enough to show all four
    /// dashboard cards without needing to scroll.
    private let snapshotSize = CGSize(width: 390, height: 810)

    /// iPhone 13 Pro portrait dimensions with extra height for XXXL Dynamic
    /// Type, which causes each card to expand significantly.
    private let xxxlSnapshotSize = CGSize(width: 390, height: 1300)

    private let lemmyTeal = UIColor(red: 0.0, green: 0.59, blue: 0.53, alpha: 1.0)

    // MARK: - DB seeding

    /// Inserts instance → site → person → account.
    ///
    /// Returns the GRDB autoincrement IDs for the new account and person rows.
    private func seedAccount(
        into appDatabase: AppDatabase,
        name: String,
        displayName: String?,
        numberOfPosts: Int,
        numberOfComments: Int,
        joinedDate: Date
    ) async throws -> (accountId: Int64, personRowId: Int64) {
        try await appDatabase.writer.write { db in
            try db.execute(
                sql: "INSERT INTO instance (actorId, createdAt) VALUES ('https://lemmy.world', ?)",
                arguments: [Date()]
            )
            let instanceId = db.lastInsertedRowID
            try db.execute(
                sql: "INSERT INTO site (instanceId, createdAt, updatedAt) VALUES (?, ?, ?)",
                arguments: [instanceId, Date(), Date()]
            )
            let siteId = db.lastInsertedRowID

            try db.execute(
                sql: """
                    INSERT INTO person (siteId, personId, name, displayName,
                        numberOfPosts, numberOfComments,
                        personCreatedDate, createdAt, updatedAt)
                    VALUES (?, 101, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    siteId,
                    name,
                    displayName,
                    numberOfPosts,
                    numberOfComments,
                    joinedDate,
                    Date(),
                    Date(),
                ]
            )
            let personRowId = db.lastInsertedRowID

            try db.execute(
                sql: """
                    INSERT INTO account
                        (siteId, personId, accountKeychainId,
                         isDefault, isServiceAccount, isSignedOutAccountType,
                         createdAt, updatedAt)
                    VALUES (?, ?, 'snapshot-summary', 1, 0, 0, ?, ?)
                    """,
                arguments: [siteId, personRowId, Date(), Date()]
            )
            let accountId = db.lastInsertedRowID
            return (accountId, personRowId)
        }
    }

    /// Seeds vote events at fixed UTC epoch seconds within the 18-week window
    /// (2024-11-25 through 2025-03-30 for `fixedAsOf = 2025-03-24`).
    ///
    /// Distribution across five calendar days produces visible non-zero heatmap
    /// buckets:
    ///
    /// | Date       | Votes | Bucket |
    /// |------------|-------|--------|
    /// | 2025-03-17 |     3 |      2 |
    /// | 2025-03-10 |     7 |      3 |
    /// | 2025-02-24 |     1 |      1 |
    /// | 2025-01-27 |    12 |      4 |
    /// | 2024-12-16 |     2 |      1 |
    private func seedVoteEvents(into appDatabase: AppDatabase, accountId: Int64) async throws {
        let seedings: [(epochSec: Int64, count: Int)] = [
            (1_742_169_600, 3), // 2025-03-17 Mon
            (1_741_564_800, 7), // 2025-03-10 Mon
            (1_740_355_200, 1), // 2025-02-24 Mon
            (1_737_936_000, 12), // 2025-01-27 Mon
            (1_734_307_200, 2), // 2024-12-16 Mon
        ]
        try await appDatabase.writer.write { db in
            var serverPostId: Int64 = 100
            for (epochSec, count) in seedings {
                for _ in 0..<count {
                    try db.execute(
                        sql: """
                            INSERT INTO voteEvent (accountId, entityType, entityServerId, voteAction, votedAt, communityName)
                            VALUES (?, 'post', ?, 1, ?, 'technology')
                            """,
                        arguments: [accountId, serverPostId, epochSec]
                    )
                    serverPostId += 1
                }
            }
        }
    }

    // MARK: - View hierarchy helpers

    private func hierarchyContainsLabel(_ view: UIView, text: String) -> Bool {
        if let label = view as? UILabel, !label.isHidden, label.text?.contains(text) == true {
            return true
        }
        for subview in view.subviews where hierarchyContainsLabel(subview, text: text) {
            return true
        }
        return false
    }

    /// Polls `vc.view` until `sentinel` text appears in any non-hidden `UILabel`.
    ///
    /// Suspends the main actor between polls so GRDB observation continuations
    /// can land. Calls `XCTFail` and returns if the sentinel never appears,
    /// so a blank snapshot is never recorded silently.
    private func waitUntilRendered(
        sentinel: String,
        in vc: UIViewController,
        timeout: TimeInterval = 4,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000)
            vc.view.layoutIfNeeded()
            if hierarchyContainsLabel(vc.view, text: sentinel) { return }
        }
        XCTFail(
            "SummaryViewController never rendered sentinel '\(sentinel)' within \(timeout)s — " +
                "refusing to snapshot a blank screen.",
            file: file,
            line: line
        )
    }

    // MARK: - VC construction helper

    private func makeNavController(
        vc: UIViewController,
        size: CGSize
    ) -> UINavigationController {
        let nav = UINavigationController(rootViewController: vc)
        nav.loadViewIfNeeded()
        nav.view.frame = CGRect(origin: .zero, size: size)
        nav.view.tintColor = lemmyTeal
        nav.view.layoutIfNeeded()
        return nav
    }

    // MARK: - Test: populated dashboard (light + dark)

    /// Full summary dashboard with seeded person data (display name, post/comment
    /// counts, join date) and vote events that produce non-zero heatmap buckets.
    func test_populated() async throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let appDatabase = try AppDatabase.inMemory()
            let (accountId, personRowId) = try await seedAccount(
                into: appDatabase,
                name: "lemmy_user",
                displayName: "Lemmy User",
                numberOfPosts: 127,
                numberOfComments: 342,
                joinedDate: Date(timeIntervalSince1970: 1_600_000_000) // 2020-09-13
            )
            try await seedVoteEvents(into: appDatabase, accountId: accountId)

            let dependencies = SnapshotDependencies(appDatabase: appDatabase)
            let vc = SummaryViewController(
                accountId: accountId,
                personRowId: personRowId,
                asOf: fixedAsOf,
                dependencies: dependencies
            )
            let nav = makeNavController(vc: vc, size: snapshotSize)

            await waitUntilRendered(sentinel: "Lemmy User", in: vc)
            nav.view.layoutIfNeeded()

            assertSnapshot(
                matching: nav,
                as: .image(
                    on: .iPhone13Pro,
                    size: snapshotSize,
                    traits: UITraitCollection(userInterfaceStyle: style)
                ),
                named: style == .dark ? "dark" : "light"
            )
        }
    }

    // MARK: - Test: early/empty dashboard (light + dark)

    /// Dashboard with no person record and no activity data.
    ///
    /// The async observation fires with empty `SummaryStats` (all counts zero,
    /// no name/dates). The identity strip renders blank labels; the stat tiles
    /// show "0". The heatmap grid is all-empty (bucket 0). We poll for the
    /// "Posts" tile caption which is configured when any `SummaryStats` arrives
    /// (even empty), so the tiles area is definitely rendered before we snapshot.
    func test_empty() async throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let appDatabase = try AppDatabase.inMemory()

            let dependencies = SnapshotDependencies(appDatabase: appDatabase)
            let vc = SummaryViewController(
                accountId: 1,
                personRowId: nil,
                asOf: fixedAsOf,
                dependencies: dependencies
            )
            let nav = makeNavController(vc: vc, size: snapshotSize)

            // The observation fires with zero-value SummaryStats; poll for the
            // "Posts" tile caption (set by statTilesView.configure) to confirm
            // the observation delivered and the tiles are configured.
            await waitUntilRendered(sentinel: "Posts", in: vc)
            nav.view.layoutIfNeeded()

            assertSnapshot(
                matching: nav,
                as: .image(
                    on: .iPhone13Pro,
                    size: snapshotSize,
                    traits: UITraitCollection(userInterfaceStyle: style)
                ),
                named: style == .dark ? "dark" : "light"
            )
        }
    }

    // MARK: - Test: votes-empty heatmap state

    /// The heatmap card in `.votes` metric mode with zero vote events in the
    /// 18-week window. The note label "Votes appear here from now on…" must be
    /// visible.
    ///
    /// Rendered as a standalone `SummaryHeatmapCardView` at a fixed width so
    /// the card is visible without snapshotting the full scrollable screen.
    func test_votesEmptyHeatmapCard() throws {
        let appDatabase = try AppDatabase.inMemory()
        let emptySeries = try appDatabase.heatmapSeries(
            accountId: 1,
            personRowId: nil,
            metric: .votes,
            asOf: fixedAsOf
        )

        let cardWidth: CGFloat = 358 // 390 - 16 margins each side
        let card = SummaryHeatmapCardView()
        card.tintColor = lemmyTeal
        card.configure(series: emptySeries)

        // Measure intrinsic height.
        card.frame = CGRect(x: 0, y: 0, width: cardWidth, height: 3000)
        card.setNeedsLayout()
        card.layoutIfNeeded()
        let height = card.systemLayoutSizeFitting(
            CGSize(width: cardWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        card.frame = CGRect(x: 0, y: 0, width: cardWidth, height: height)
        card.layoutIfNeeded()

        for style in [UIUserInterfaceStyle.light, .dark] {
            assertSnapshot(
                matching: card,
                as: .image(
                    size: card.bounds.size,
                    traits: UITraitCollection(userInterfaceStyle: style)
                ),
                named: style == .dark ? "dark" : "light"
            )
        }
    }

    // MARK: - Test: Dynamic Type XXXL

    /// Full summary dashboard at `.accessibilityExtraExtraExtraLarge` content
    /// size to verify that no label or control uses a fixed font size.
    func test_dynamicTypeXXXL() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, personRowId) = try await seedAccount(
            into: appDatabase,
            name: "lemmy_user",
            displayName: "Lemmy User",
            numberOfPosts: 127,
            numberOfComments: 342,
            joinedDate: Date(timeIntervalSince1970: 1_600_000_000)
        )
        try await seedVoteEvents(into: appDatabase, accountId: accountId)

        let dependencies = SnapshotDependencies(appDatabase: appDatabase)
        let vc = SummaryViewController(
            accountId: accountId,
            personRowId: personRowId,
            asOf: fixedAsOf,
            dependencies: dependencies
        )
        let nav = makeNavController(vc: vc, size: xxxlSnapshotSize)

        await waitUntilRendered(sentinel: "Lemmy User", in: vc)
        nav.view.layoutIfNeeded()

        assertSnapshot(
            matching: nav,
            as: .image(
                on: .iPhone13Pro,
                size: xxxlSnapshotSize,
                traits: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
            ),
            named: "xxxl"
        )
    }
}
