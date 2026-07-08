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

/// Screen snapshots of the Explorer instance detail (feature #4) across the
/// design's state matrix — open / application / closed / NSFW / suspicious /
/// tiny (unknown uptime) / missing (graceful degradation) — in light and dark.
///
/// Rendered at a pinned `ViewImageConfig` (iPhone 13 Pro width/scale/safe-area) at
/// the full scroll-content height, so admins and communities below the fold are
/// always captured. Records are deterministic: instance icons/banners are left nil
/// so placeholder marks render without async image loading. Admins and communities
/// are seeded into the in-memory DB before the VC is constructed so the synchronous
/// cache-first render captures them at snapshot time.
@MainActor
final class InstanceDetailSnapshotTests: XCTestCase {
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

    /// Stub whose probe returns a fixed `InstanceMetadata` (or `nil`). With the
    /// default `nil` the badge stays hidden and the Signups row keeps its
    /// Explorer value, so existing refs need no re-recording; passing a value
    /// drives the badge-version + live-signups variant.
    private struct StubNodeInfoService: NodeInfoServiceType {
        var metadataResult: InstanceMetadata?

        func detect(host _: String, maxAge _: TimeInterval) async -> NodeInfoDetection {
            guard let metadataResult else { return .unknown }
            return .known(metadataResult.software, version: metadataResult.version)
        }

        func metadata(host _: String, maxAge _: TimeInterval) async -> InstanceMetadata? {
            metadataResult
        }
    }

    /// A minimal dependency container.
    @MainActor
    struct SnapshotDependencies: HasVoid, HasImageService, HasAccountService, HasAlertService, HasAppDatabase, HasNodeInfoService {
        let imageService: ImageServiceType
        let accountService: AccountServiceType
        let alertService: AlertServiceType
        let appDatabase: AppDatabase
        let nodeInfoService: NodeInfoServiceType
    }

    private func makeDependencies(metadata: InstanceMetadata? = nil) throws -> SnapshotDependencies {
        let appDatabase = try AppDatabase.inMemory()
        return SnapshotDependencies(
            imageService: StaticImageService(),
            accountService: AccountService(appDatabase: appDatabase),
            alertService: AlertService(),
            appDatabase: appDatabase,
            nodeInfoService: StubNodeInfoService(metadataResult: metadata)
        )
    }

    // MARK: - Snapshot helper

    private func assertScreens(
        _ record: ExplorerInstanceRecord,
        adminCount: Int = 3,
        communityCount: Int = 3,
        testName: String = #function,
        line: UInt = #line
    ) throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let dependencies = try makeDependencies()
            try seedInstanceSnapshot(
                record,
                into: dependencies.appDatabase,
                adminCount: adminCount,
                communityCount: communityCount
            )
            let viewController = InstanceDetailViewController(record: record, dependencies: dependencies)
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

    /// Like `assertScreens`, but seeds a live `InstanceMetadata` into the stub
    /// and awaits the VC's async metadata probe (badge + Signups override)
    /// before capturing. Uses a `.example` host so the incidental site-info
    /// fetch fails fast (non-resolvable) and can never mutate the seeded render.
    private func assertLiveMetadataScreens(
        _ record: ExplorerInstanceRecord,
        metadata: InstanceMetadata,
        adminCount: Int = 3,
        communityCount: Int = 3,
        testName: String = #function,
        line: UInt = #line
    ) async throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let dependencies = try makeDependencies(metadata: metadata)
            try seedInstanceSnapshot(
                record,
                into: dependencies.appDatabase,
                adminCount: adminCount,
                communityCount: communityCount
            )
            let viewController = InstanceDetailViewController(record: record, dependencies: dependencies)
            let navigationController = UINavigationController(rootViewController: viewController)

            navigationController.loadViewIfNeeded()
            navigationController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            navigationController.view.layoutIfNeeded()

            // The badge + live Signups are applied by an async probe; poll until
            // the badge resolves before capturing (fail loudly if it never does).
            let deadline = Date().addingTimeInterval(2)
            while viewController.snapshotSoftwareBadgeText == nil {
                if Date() > deadline {
                    XCTFail("Live metadata badge never resolved", line: line)
                    return
                }
                try await Task.sleep(nanoseconds: 5_000_000)
                await Task.yield()
            }
            navigationController.view.layoutIfNeeded()

            let contentHeight = viewController.snapshotContentHeight
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

    func test_open() throws {
        try assertScreens(Fixtures.world)
    }

    func test_application() throws {
        try assertScreens(Fixtures.beehaw)
    }

    func test_closed() throws {
        try assertScreens(Fixtures.hexbear)
    }

    func test_nsfw() throws {
        try assertScreens(Fixtures.nsfw)
    }

    func test_suspicious() throws {
        // Suspicious instance: 0 admins → .anonymous state
        try assertScreens(Fixtures.suspicious, adminCount: 0, communityCount: 2)
    }

    func test_tiny_unknownUptime() throws {
        try assertScreens(Fixtures.tiny, adminCount: 1, communityCount: 2)
    }

    func test_missing_gracefulDegradation() throws {
        // Missing: 0 admins (unavailable) + 0 communities (unavailable)
        try assertScreens(Fixtures.missing, adminCount: 0, communityCount: 0)
    }

    /// A live NodeInfo probe drives the header badge ("Lemmy 0.19.11" — the live
    /// version) and unifies the details-card Software row on the same live
    /// version ("v0.19.11", replacing the directory's "v0.19.5"), plus the
    /// Signups row's color (green, from the live `openRegistrations`) — the
    /// Signups text stays "Open signups", matching the directory fallback
    /// verbatim so that row never visibly changes wording, only value/color,
    /// across the probe.
    func test_liveMetadata_badgeVersionAndSignups() async throws {
        let metadata = InstanceMetadata(
            software: .lemmy,
            version: "0.19.11",
            openRegistrations: true,
            usersTotal: nil,
            usersActiveMonth: nil,
            usersActiveHalfyear: nil,
            localPosts: nil,
            localComments: nil
        )
        try await assertLiveMetadataScreens(Fixtures.liveDemo, metadata: metadata)
    }

    // MARK: - Fixtures (mirror the Spud Design instance-detail fixtures)

    enum Fixtures {
        static let world = ExplorerInstanceRecord(
            baseurl: "lemmy.world", url: "https://lemmy.world", name: "Lemmy World",
            descriptionText: "The largest general-purpose Lemmy server. Big, fast and well-moderated — a safe all-rounder if you are not sure where to land.",
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
            descriptionText: "Small, kind and carefully curated. Joining needs a short application — they read every one to keep the garden tidy.",
            version: "0.19.3",
            usersTotal: 92000, usersActiveMonth: 4100, usersActiveHalfYear: 15000,
            numberOfCommunities: 180, numberOfPosts: 210_000,
            uptimeAllTime: 99.9, latency: 88,
            regMode: 1, isOpenRegistration: false, isNsfw: false,
            score: 0.91, isSuspicious: false,
            langs: "en", tags: "Community,Wholesome",
            blocksIncoming: 51, blocksOutgoing: 128
        )

        static let hexbear = ExplorerInstanceRecord(
            baseurl: "hexbear.net", url: "https://hexbear.net", name: "Hexbear",
            descriptionText: "A large, opinionated community with a strong house style. Registrations are currently closed to new members.",
            version: "0.19.5",
            usersTotal: 64000, usersActiveMonth: 6200, usersActiveHalfYear: 19000,
            numberOfCommunities: 95, numberOfPosts: 900_000,
            uptimeAllTime: 98.4, latency: 210,
            regMode: 0, isOpenRegistration: false, isNsfw: false,
            score: 0.71, isSuspicious: false,
            langs: "en", tags: "Politics,Culture",
            blocksIncoming: 240, blocksOutgoing: 60
        )

        static let nsfw = ExplorerInstanceRecord(
            baseurl: "lemmynsfw.com", url: "https://lemmynsfw.com", name: "Lemmynsfw",
            descriptionText: "An adults-only server for NSFW communities. You must be 18+ and have NSFW content enabled to take part.",
            version: "0.19.5",
            usersTotal: 140_000, usersActiveMonth: 12000, usersActiveHalfYear: 38000,
            numberOfCommunities: 420, numberOfPosts: 600_000,
            uptimeAllTime: 99.2, latency: 160,
            regMode: 2, isOpenRegistration: true, isNsfw: true,
            score: 0.80, isSuspicious: false,
            langs: "en", tags: "NSFW,Adult",
            blocksIncoming: 30, blocksOutgoing: 12
        )

        static let suspicious = ExplorerInstanceRecord(
            baseurl: "lemy-xyz.top", url: "https://lemy-xyz.top", name: "Lemy XYZ",
            descriptionText: "Recently registered, anonymous operator. Federates aggressively and is blocked by a large share of the network.",
            version: "0.18.1",
            usersTotal: 54000, usersActiveMonth: 900, usersActiveHalfYear: 2100,
            numberOfCommunities: 2100, numberOfPosts: 88000,
            uptimeAllTime: 71, latency: 820,
            regMode: 2, isOpenRegistration: true, isNsfw: true,
            score: 0.22, isSuspicious: true,
            langs: "en", tags: "Unknown",
            blocksIncoming: 412, blocksOutgoing: 9
        )

        static let tiny = ExplorerInstanceRecord(
            baseurl: "spud.cafe", url: "https://spud.cafe", name: "Spud Cafe",
            descriptionText: "A cozy little corner run by one admin.",
            version: "0.19.4",
            usersTotal: 312, usersActiveMonth: 47, usersActiveHalfYear: 120,
            numberOfCommunities: 12, numberOfPosts: 1400,
            uptimeAllTime: nil, latency: nil,
            regMode: 2, isOpenRegistration: true, isNsfw: false,
            score: 0.58, isSuspicious: false,
            langs: "en", tags: "Hobby",
            blocksIncoming: 0, blocksOutgoing: 2
        )

        /// Open, healthy instance on a non-resolvable `.example` host — used for
        /// the live-metadata variant so the incidental site-info fetch can't hit
        /// the network. Directory version 0.19.5 is overridden by the live probe's
        /// 0.19.11 in both the header badge and the details-card Software row; the
        /// "Open signups" text is identical in both the directory fallback and the
        /// live override (only the color can change).
        static let liveDemo = ExplorerInstanceRecord(
            baseurl: "lemmy.example", url: "https://lemmy.example", name: "Lemmy Example",
            descriptionText: "A demo instance for snapshotting the live NodeInfo software badge and Signups override.",
            version: "0.19.5",
            usersTotal: 240_000, usersActiveMonth: 9800, usersActiveHalfYear: 42000,
            numberOfCommunities: 620, numberOfPosts: 1_100_000,
            uptimeAllTime: 99.5, latency: 120,
            regMode: 2, isOpenRegistration: true, isNsfw: false,
            score: 0.88, isSuspicious: false,
            langs: "en", tags: "General,Demo",
            blocksIncoming: 12, blocksOutgoing: 40
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
