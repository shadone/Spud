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

/// Screen snapshots of the in-app `InstanceExploreViewController` (post-login
/// instance browse). Covers: populated state (world), suspicious/anonymous admins,
/// missing/unavailable admins + communities, a sidebar variant, and a joined-community
/// variant.
///
/// Rendered at a pinned `ViewImageConfig` (iPhone 13 Pro width/scale/safe-area) at
/// the full scroll-content height, so admins and communities below the fold are
/// always captured. Admins, communities and sidebar are seeded into the in-memory DB
/// before the VC is constructed so the synchronous cache-first render captures them.
@MainActor
final class InstanceExploreSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Pin the process-wide accent so renders don't depend on the sim's
        // persisted accent preference. See `SnapshotDeterminism.pinAccent()`.
        SnapshotDeterminism.pinAccent()
        // Pin the host scene's status bar hidden so nav-hosted / key-window
        // captures are immune to the sim's persisted orientation state (the
        // 44pt-shift regression). See
        // `SnapshotDeterminism.pinStatusBarHidden()`.
        SnapshotDeterminism.pinStatusBarHidden()
    }

    /// Stub that always returns `.unknown` so the badge stays hidden and
    /// no existing snapshot ref needs re-recording.
    private struct StubNodeInfoService: NodeInfoServiceType {
        func detect(host _: String, maxAge _: TimeInterval) async -> NodeInfoDetection {
            .unknown
        }
    }

    @MainActor
    private struct SnapshotDependencies: HasVoid, HasImageService, HasAccountService, HasAlertService, HasAppDatabase, HasMetaCommunityService, HasNodeInfoService {
        let imageService: ImageServiceType
        let accountService: AccountServiceType
        let alertService: AlertServiceType
        let appDatabase: AppDatabase
        let metaCommunityService: MetaCommunityServiceType
        let nodeInfoService: NodeInfoServiceType
    }

    private func makeDependencies() throws -> SnapshotDependencies {
        let appDatabase = try AppDatabase.inMemory()
        return SnapshotDependencies(
            imageService: StaticImageService(),
            accountService: AccountService(appDatabase: appDatabase),
            alertService: AlertService(),
            appDatabase: appDatabase,
            metaCommunityService: StubMetaCommunityService(),
            nodeInfoService: StubNodeInfoService()
        )
    }

    // MARK: - Snapshot helper

    private func assertScreens(
        _ record: ExplorerInstanceRecord,
        adminCount: Int = 3,
        communityCount: Int = 3,
        sidebar: String? = nil,
        joinedCommunityUrls: Set<String> = [],
        testName: String = #function,
        line: UInt = #line
    ) throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let dependencies = try makeDependencies()
            try seedInstanceSnapshot(
                record,
                into: dependencies.appDatabase,
                adminCount: adminCount,
                communityCount: communityCount,
                sidebar: sidebar
            )
            // Use a placeholder keychainId — the explore VC only uses it for
            // the join-gate check (isSignedOut), which won't fire in a snapshot.
            let accountKeychainId = "snapshot-signed-out"
            let viewController = InstanceExploreViewController(
                record: record,
                accountKeychainId: accountKeychainId,
                dependencies: dependencies,
                initialJoinedCommunityUrls: joinedCommunityUrls
            )
            let navigationController = UINavigationController(rootViewController: viewController)

            // Load and lay out so snapshotContentHeight reflects the full content.
            navigationController.loadViewIfNeeded()
            navigationController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            navigationController.view.layoutIfNeeded()

            let contentHeight = viewController.snapshotContentHeight
            // Add chrome margin for the nav bar and bottom safe area.
            let totalHeight = max(844, contentHeight + 120)
            let size = CGSize(width: 390, height: totalHeight)

            assertSnapshot(
                matching: navigationController,
                as: .image(
                    on: .deterministicPhone,
                    size: size,
                    traits: UITraitCollection(userInterfaceStyle: style)
                ),
                named: style == .dark ? "dark" : "light",
                testName: testName,
                line: line
            )
        }
    }

    // MARK: - States

    func test_world_populated() throws {
        try assertScreens(Fixtures.world)
    }

    func test_world_withSidebar() throws {
        let sidebar = """
            ## Welcome to Lemmy World

            The largest general-purpose Lemmy server. Join us for news, tech, culture and more.

            **Rules:** Be kind. No spam. Follow Lemmy's [Code of Conduct](https://join-lemmy.org/docs/code_of_conduct.html).
            """
        try assertScreens(Fixtures.world, sidebar: sidebar)
    }

    func test_world_joinedCommunity() throws {
        // One community pre-marked as joined to verify the joined row state renders correctly.
        let joinedUrl = "https://lemmy.world/c/community0"
        try assertScreens(Fixtures.world, joinedCommunityUrls: [joinedUrl])
    }

    func test_suspicious_anonymousAdmins() throws {
        // Suspicious + 0 admins → .anonymous state
        try assertScreens(Fixtures.suspicious, adminCount: 0, communityCount: 2)
    }

    func test_missing_unavailable() throws {
        // 0 admins → .unavailable, 0 communities → unavailable card
        try assertScreens(Fixtures.missing, adminCount: 0, communityCount: 0)
    }

    func test_beehaw_populated() throws {
        try assertScreens(Fixtures.beehaw)
    }

    // MARK: - Fixtures

    private enum Fixtures {
        static let world = ExplorerInstanceRecord(
            baseurl: "lemmy.world", url: "https://lemmy.world", name: "Lemmy World",
            descriptionText: "The largest general-purpose Lemmy server.",
            version: "0.19.5",
            usersTotal: 1_200_000, usersActiveMonth: 58000, usersActiveHalfYear: 184_000,
            numberOfCommunities: 32000, numberOfPosts: 4_800_000,
            uptimeAllTime: 99.7, latency: 142,
            regMode: 2, isOpenRegistration: true, isNsfw: false,
            score: 0.96, isSuspicious: false,
            langs: "en", tags: "General,News,Technology",
            blocksIncoming: 9, blocksOutgoing: 34
        )

        static let beehaw = ExplorerInstanceRecord(
            baseurl: "beehaw.org", url: "https://beehaw.org", name: "Beehaw",
            descriptionText: "Small, kind and carefully curated.",
            version: "0.19.3",
            usersTotal: 92000, usersActiveMonth: 4100, usersActiveHalfYear: 15000,
            numberOfCommunities: 180, numberOfPosts: 210_000,
            uptimeAllTime: 99.9, latency: 88,
            regMode: 1, isOpenRegistration: false, isNsfw: false,
            score: 0.91, isSuspicious: false,
            langs: "en", tags: "Community,Wholesome",
            blocksIncoming: 51, blocksOutgoing: 128
        )

        static let suspicious = ExplorerInstanceRecord(
            baseurl: "lemy-xyz.top", url: "https://lemy-xyz.top", name: "Lemy XYZ",
            descriptionText: "Recently registered, anonymous operator.",
            version: "0.18.1",
            usersTotal: 54000, usersActiveMonth: 900, usersActiveHalfYear: 2100,
            numberOfCommunities: 2100, numberOfPosts: 88000,
            uptimeAllTime: 71, latency: 820,
            regMode: 2, isOpenRegistration: true, isNsfw: true,
            score: 0.22, isSuspicious: true,
            langs: "en", tags: "Unknown",
            blocksIncoming: 412, blocksOutgoing: 9
        )

        static let missing = ExplorerInstanceRecord(
            baseurl: "fedi.example", url: "https://fedi.example", name: "Fedi One",
            descriptionText: nil,
            version: nil,
            usersTotal: 6400, usersActiveMonth: 0, usersActiveHalfYear: 0,
            numberOfCommunities: 0, numberOfPosts: 0,
            uptimeAllTime: nil, latency: nil,
            regMode: -1, isOpenRegistration: false, isNsfw: false,
            score: 0, isSuspicious: false,
            langs: nil, tags: nil,
            blocksIncoming: nil, blocksOutgoing: nil
        )
    }
}
