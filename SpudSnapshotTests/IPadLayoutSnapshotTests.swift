//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import SpudDataKit
import SwiftUI
import UIKit
import XCTest
@testable import Spud

/// iPad-landscape snapshot of Discover: verifies the rails render as an adaptive
/// grid (not a horizontal carousel) and the directory column is capped rather than
/// stretching full-bleed across the wide canvas.
///
/// Uses `.image(on: .iPadPro11(.landscape), traits:)` which pins an explicit
/// device size, so any simulator works — no need to run on a specific device or
/// runtime for these refs.
@MainActor
final class IPadLayoutSnapshotTests: XCTestCase {
    private let teal = Color(uiColor: UIColor(red: 0, green: 0x96 / 255, blue: 0x87 / 255, alpha: 1))

    @MainActor
    private struct SnapshotDependencies: HasAccountService, HasAlertService, HasAppDatabase, HasPreferencesService {
        let accountService: AccountServiceType
        let alertService: AlertServiceType
        let appDatabase: AppDatabase
        let preferencesService: PreferencesServiceType
    }

    func test_discover_populated_ipad_landscape() async throws {
        let appDatabase = try AppDatabase.inMemory()
        try await seedDiscoverCommunities(into: appDatabase)

        let dependencies = SnapshotDependencies(
            accountService: AccountService(appDatabase: appDatabase),
            alertService: AlertService(),
            appDatabase: appDatabase,
            preferencesService: PreferencesService()
        )
        let viewModel = DiscoverViewModel(
            accountScope: dependencies.accountService.scope(forAccountKeychainId: "snapshot-signed-out"),
            isSignedIn: false,
            dependencies: dependencies,
            onOpenCommunity: { _ in },
            onOpenPack: { _ in },
            onOpenInstance: { _ in },
            onSeeAllCommunities: { _, _ in },
            onSeeAllInstances: { _, _ in },
            onRequestSignIn: { }
        )

        // The rails arrive via an async observation; wait for them.
        try await waitUntil {
            !viewModel.isLoading && viewModel.trending.count > DiscoverViewModel.railCarouselCount
        }

        let view = DiscoverView(viewModel: viewModel, accent: teal)
            .environment(\.imageService, StaticImageService())
        let host = UIHostingController(rootView: view)

        assertSnapshot(
            matching: host,
            as: .image(
                on: .iPadPro11(.landscape),
                traits: UITraitCollection(userInterfaceStyle: .light)
            ),
            named: "light"
        )
    }

    // MARK: - Profile banner iPad snapshot

    /// Verifies that the profile banner is centred within a capped column on iPad
    /// (regular size class) and does not render as a full-width filmstrip.
    ///
    /// Uses nil image URLs so the view renders the deterministic placeholder
    /// synchronously — no async settling needed.
    func test_profileBanner_ipad_landscape_light() {
        let view = makeProfileBannerFixture()
        let host = UIHostingController(rootView: AnyView(view))
        host.view.frame = CGRect(
            origin: .zero,
            size: ViewImageConfig.iPadPro11(.landscape).size ?? CGSize(width: 1194, height: 834)
        )
        host.view.layoutIfNeeded()
        assertSnapshot(
            matching: host,
            as: .image(
                on: .iPadPro11(.landscape),
                traits: UITraitCollection(userInterfaceStyle: .light)
            ),
            named: "light"
        )
    }

    // MARK: - Profile banner helpers

    /// Builds a display-only `ProfileBannerHeaderView` with nil URLs (placeholder)
    /// suitable for a synchronous snapshot — mirrors `ProfileBannerSnapshotTests.makeBannerView`.
    private func makeProfileBannerFixture() -> some View {
        ProfileBannerHeaderView(
            bannerUrl: nil,
            avatarUrl: nil,
            name: "testuser",
            isUploadingBanner: false,
            isUploadingAvatar: false,
            onPickBanner: nil,
            onPickAvatar: nil,
            onRemoveBanner: nil,
            onRemoveAvatar: nil
        )
        .environment(\.imageService, StaticImageService())
        .background(Color(UIColor.systemBackground))
    }

    // MARK: - Discover helpers

    /// Poll on the main actor until `condition` holds, failing loudly if it never does.
    private func waitUntil(
        timeout: TimeInterval = 5,
        _ condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Discover landing did not populate within \(timeout)s")
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    /// Seed a deterministic set of Explorer communities across four hosts —
    /// mirrors the fixture in `DiscoverScreenSnapshotTests`.
    private func seedDiscoverCommunities(into appDatabase: AppDatabase) async throws {
        let hosts = ["lemmy.world", "beehaw.org", "lemmy.ml", "sh.itjust.works"]
        let topics = [
            "Technology", "Gaming", "Science", "News", "Movies", "Music",
            "Books", "Art", "Food", "Travel", "Fitness", "Photography",
            "Programming", "Privacy", "Space", "History", "Nature", "Pets",
            "Cars", "Finance", "DIY", "Comics", "Sports", "Memes",
        ]
        try await appDatabase.writer.write { db in
            for (index, topic) in topics.enumerated() {
                let host = hosts[index % hosts.count]
                let name = topic.lowercased()
                let weight = Int64(topics.count - index)
                var record = ExplorerCommunityRecord(
                    url: "https://\(host)/c/\(name)",
                    baseurl: host,
                    name: name,
                    title: topic,
                    isNsfw: false,
                    numberOfSubscribers: weight * 1000,
                    numberOfPosts: weight * 200,
                    numberOfComments: weight * 800,
                    usersActiveDay: weight * 30,
                    usersActiveWeek: weight * 150,
                    usersActiveMonth: weight * 400,
                    usersActiveHalfYear: weight * 900,
                    score: Double(weight) / Double(topics.count),
                    isSuspicious: false
                )
                try record.insert(db)
            }
        }
    }
}
