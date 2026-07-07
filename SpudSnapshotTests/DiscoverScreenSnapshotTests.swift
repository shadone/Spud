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

/// Full-screen snapshot of the assembled Discover landing (`DiscoverView`) — the
/// rails (Trending / Rising / Browse by instance) with their "See all" headers
/// over the All-communities directory. The component-level building blocks are
/// covered by `DiscoverSnapshotTests`; this verifies they compose into the right
/// landing (section order, headers, the See-all affordance appearing when a rail
/// overflows the carousel).
///
/// The view model fills its rails from an **async** GRDB observation
/// (`observeExplorerCommunityListRows`), so the directory is seeded first, then the
/// test polls until the rails populate before rendering (and fails loudly if they
/// never do, rather than recording a blank). Signed-out, so "Because you follow"
/// is omitted and no account row is needed. `.image(size:traits:)` is device- and
/// runtime-sensitive — record on the reference iPhone 17 Pro, iOS 26.3.
@MainActor
final class DiscoverScreenSnapshotTests: XCTestCase {
    private let teal = Color(uiColor: UIColor(red: 0, green: 0x96 / 255, blue: 0x87 / 255, alpha: 1))

    @MainActor
    private struct SnapshotDependencies: HasAccountService, HasAlertService, HasAppDatabase, HasPreferencesService {
        let accountService: AccountServiceType
        let alertService: AlertServiceType
        let appDatabase: AppDatabase
        let preferencesService: PreferencesServiceType
    }

    func test_discoverLanding_populated() async throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let appDatabase = try AppDatabase.inMemory()
            try await seedDiscoverCommunities(into: appDatabase)

            let dependencies = SnapshotDependencies(
                accountService: AccountService(appDatabase: appDatabase),
                alertService: AlertService(),
                appDatabase: appDatabase,
                preferencesService: SnapshotPreferences.ephemeral()
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

            // The rails arrive via an async observation; wait for them (then the
            // landing is no longer the loading spinner).
            try await waitUntil {
                !viewModel.isLoading && viewModel.trending.count > DiscoverViewModel.railCarouselCount
            }

            let view = DiscoverView(viewModel: viewModel, accent: teal)
                .environment(\.imageService, StaticImageService())
            let host = UIHostingController(rootView: view)
            let size = CGSize(width: 390, height: 2200)
            host.view.frame = CGRect(origin: .zero, size: size)
            host.view.layoutIfNeeded()

            assertSnapshot(
                matching: host,
                as: .image(size: size, traits: UITraitCollection(traitsFrom: [
                    UITraitCollection(userInterfaceStyle: style),
                    SnapshotDeterminism.contentSizeTrait,
                ])),
                named: style == .dark ? "dark" : "light"
            )
        }
    }

    // MARK: - Helpers

    /// Poll on the main actor until `condition` holds, failing the test if it never
    /// does — so a landing that never renders fails loudly instead of recording a
    /// blank reference.
    private func waitUntil(
        timeout: TimeInterval = 5,
        _ condition: () -> Bool,
        function: StaticString = #function,
        line: UInt = #line
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Discover landing did not populate within \(timeout)s", line: line)
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    /// Seed a deterministic set of Explorer communities across four hosts with
    /// descending activity, so Trending overflows its carousel (exercising "See
    /// all"), Rising surfaces the smaller high-engagement ones, and Browse-by-
    /// instance lists every host.
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
                let weight = Int64(topics.count - index) // descending
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
