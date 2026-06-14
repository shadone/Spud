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
/// Rendered at a pinned `ViewImageConfig` (iPhone 13 Pro size/scale/safe-area),
/// so the references are device-independent — they record and verify identically
/// on any simulator. Records are deterministic: instance icons/banners are left
/// nil so the placeholder marks render without any async image loading.
@MainActor
final class InstanceDetailSnapshotTests: XCTestCase {
    /// A minimal dependency container. The detail view controller only stores
    /// these services (it touches them on user actions, not while rendering), so
    /// lightweight real implementations + an in-memory account service suffice.
    @MainActor
    private struct SnapshotDependencies: HasVoid, HasImageService, HasAccountService, HasAlertService {
        let imageService: ImageServiceType
        let accountService: AccountServiceType
        let alertService: AlertServiceType
    }

    private func makeDependencies() throws -> SnapshotDependencies {
        let appDatabase = try AppDatabase.inMemory()
        return SnapshotDependencies(
            imageService: StaticImageService(),
            accountService: AccountService(appDatabase: appDatabase),
            alertService: AlertService()
        )
    }

    private func assertScreens(
        _ record: ExplorerInstanceRecord,
        testName: String = #function,
        line: UInt = #line
    ) throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let dependencies = try makeDependencies()
            let viewController = InstanceDetailViewController(record: record, dependencies: dependencies)
            let navigationController = UINavigationController(rootViewController: viewController)
            assertSnapshot(
                matching: navigationController,
                as: .image(on: .iPhone13Pro, traits: UITraitCollection(userInterfaceStyle: style)),
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
        try assertScreens(Fixtures.suspicious)
    }

    func test_tiny_unknownUptime() throws {
        try assertScreens(Fixtures.tiny)
    }

    func test_missing_gracefulDegradation() throws {
        try assertScreens(Fixtures.missing)
    }

    // MARK: - Fixtures (mirror the Spud Design instance-detail fixtures)

    private enum Fixtures {
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
