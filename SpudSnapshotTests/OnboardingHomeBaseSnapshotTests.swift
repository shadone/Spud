//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import GRDB
import SnapshotTesting
import SpudDataKit
import UIKit
import XCTest
@testable import Spud

/// Screen snapshots of the "Pick your home base" onboarding instance picker
/// (slice 2) in light and dark.
///
/// Rendered at a pinned `ViewImageConfig` (iPhone 13 Pro size/scale/safe-area)
/// so the references are device-independent — they record and verify identically
/// on any simulator. The Explorer directory is seeded into an in-memory
/// `AppDatabase` so `explorerSiteListRowsSync()` returns deterministic cards;
/// icon URLs are left nil so the lettered gradient placeholders render with no
/// async image loading. The brand "Lemmy" teal is pinned on the root so the
/// accent-tinted controls (recommended border + pill, globe, Continue) match the
/// runtime window `tintColor`.
@MainActor
final class OnboardingHomeBaseSnapshotTests: XCTestCase {
    private let lemmyTeal = UIColor(red: 0, green: 0x96 / 255, blue: 0x87 / 255, alpha: 1)

    /// Stub that always returns `.unknown` so the badge stays hidden and
    /// no existing snapshot ref needs re-recording.
    private struct StubNodeInfoService: NodeInfoServiceType {
        func detect(host _: String, maxAge _: TimeInterval) async -> NodeInfoDetection {
            .unknown
        }
    }

    @MainActor
    private struct SnapshotDependencies:
        HasVoid,
        HasAppDatabase,
        HasImageService,
        HasAccountService,
        HasAlertService,
        HasExplorerService,
        HasNodeInfoService
    {
        let appDatabase: AppDatabase
        let imageService: ImageServiceType
        let accountService: AccountServiceType
        let alertService: AlertServiceType
        let explorerService: ExplorerServiceType
        let nodeInfoService: NodeInfoServiceType
    }

    /// Builds an in-memory database seeded with the recommended-instance fixtures,
    /// then a dependency container around it. The services are real but never
    /// exercised during a render.
    private func makeDependencies() throws -> SnapshotDependencies {
        let appDatabase = try AppDatabase.inMemory()
        try appDatabase.writer.write { db in
            for record in Fixtures.all {
                var record = record
                try record.insert(db)
            }
        }
        return SnapshotDependencies(
            appDatabase: appDatabase,
            imageService: StaticImageService(),
            accountService: AccountService(appDatabase: appDatabase),
            alertService: AlertService(),
            explorerService: ExplorerService(appDatabase: appDatabase),
            nodeInfoService: StubNodeInfoService()
        )
    }

    private func assertScreens(
        testName: String = #function,
        line: UInt = #line
    ) throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let dependencies = try makeDependencies()
            let viewController = OnboardingHomeBaseViewController(dependencies: dependencies)
            let navigationController = UINavigationController(rootViewController: viewController)
            navigationController.view.tintColor = lemmyTeal
            viewController.view.tintColor = lemmyTeal
            assertSnapshot(
                matching: navigationController,
                as: .image(on: .deterministicPhone, traits: UITraitCollection(userInterfaceStyle: style)),
                named: style == .dark ? "dark" : "light",
                testName: testName,
                line: line
            )
        }
    }

    func test_homeBase() throws {
        try assertScreens()
    }

    // MARK: - Fixtures

    /// Three recommended instances with descending Explorer scores so the ranking
    /// is deterministic. `iconUrl` is nil so the lettered gradient placeholders
    /// render without any async image load.
    private enum Fixtures {
        static let world = ExplorerInstanceRecord(
            baseurl: "lemmy.world", url: "https://lemmy.world", name: "Lemmy World",
            descriptionText: "The largest general-purpose Lemmy server. Big, fast and well-moderated — a safe all-rounder if you are not sure where to land.",
            usersTotal: 1_200_000,
            regMode: 2, isOpenRegistration: true, isNsfw: false,
            score: 0.96,
            langs: "en"
        )

        static let lemmyml = ExplorerInstanceRecord(
            baseurl: "lemmy.ml", url: "https://lemmy.ml", name: "Lemmy ML",
            descriptionText: "The flagship instance run by the Lemmy developers. General-purpose with a tech and open-source leaning.",
            usersTotal: 180_000,
            regMode: 1, isOpenRegistration: false, isNsfw: false,
            score: 0.88,
            langs: "en"
        )

        static let beehaw = ExplorerInstanceRecord(
            baseurl: "beehaw.org", url: "https://beehaw.org", name: "Beehaw",
            descriptionText: "Small, kind and carefully curated. Joining needs a short application — they read every one to keep the garden tidy.",
            usersTotal: 92000,
            regMode: 1, isOpenRegistration: false, isNsfw: false,
            score: 0.84,
            langs: "en"
        )

        static let all = [world, lemmyml, beehaw]
    }
}
