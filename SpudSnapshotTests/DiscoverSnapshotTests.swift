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

/// Snapshots of the Discover (Community Explorer) SwiftUI building blocks across
/// their visual states, each in light and dark:
///
/// - `SubscribeButton`: the idle "Subscribe" pill and the "Subscribed" confirmation.
/// - `DiscoverCommunityRow`: a plain directory row, one collapsing same-name
///   variants ("also on N servers" badge), and one showing the inline Subscribe
///   control in its subscribed state.
/// - `DiscoverTrendCard`: the Trending card and the Rising card (momentum badge).
/// - `InstanceCard`: a "Browse by instance" card.
/// - `PackCard`: a resolved starter-pack card.
///
/// Rows/cards render from hand-built `CommunityListRow` fixtures with no icon URL,
/// so `CommunityIcon` falls back to the deterministic letter tile (no async image
/// loading, no database, no network). Each view is hosted in a `UIHostingController`
/// sized to fit and rendered at a pinned display scale, so the references are
/// device-independent.
@MainActor
final class DiscoverSnapshotTests: XCTestCase {
    private let teal = Color(uiColor: UIColor(red: 0, green: 0x96 / 255, blue: 0x87 / 255, alpha: 1))

    // MARK: - SubscribeButton

    /// `.fixedSize()` so the standalone pill takes its intrinsic width; without it
    /// the sizeThatFits host under-proposes and the longer "Subscribe" label
    /// truncates (in the app the pill sits in an HStack and is never constrained).
    func test_subscribeButton_idle() {
        assertDiscoverSnapshot(SubscribeButton(state: .idle, accent: teal, action: { }).fixedSize())
    }

    func test_subscribeButton_subscribed() {
        assertDiscoverSnapshot(SubscribeButton(state: .subscribed, accent: teal, action: { }).fixedSize())
    }

    // MARK: - DiscoverCommunityRow

    func test_communityRow_plain() {
        assertDiscoverSnapshot(
            DiscoverCommunityRow(row: fixtureRow(), accent: teal, onTap: { })
                .frame(width: 390)
        )
    }

    func test_communityRow_alsoOnBadge() {
        assertDiscoverSnapshot(
            DiscoverCommunityRow(
                row: fixtureRow(alsoOn: 3, groupSubs: 540_000),
                accent: teal,
                onTap: { },
                onCompare: { }
            )
            .frame(width: 390)
        )
    }

    func test_communityRow_subscribed() {
        assertDiscoverSnapshot(
            DiscoverCommunityRow(
                row: fixtureRow(),
                accent: teal,
                onTap: { },
                subscriptionState: .subscribed,
                onSubscribe: { }
            )
            .frame(width: 390)
        )
    }

    func test_communityRow_nsfw() {
        assertDiscoverSnapshot(
            DiscoverCommunityRow(
                row: fixtureRow(name: "nsfwexample", title: "NSFW Example", nsfw: true),
                accent: teal,
                onTap: { },
                subscriptionState: .idle,
                onSubscribe: { }
            )
            .frame(width: 390)
        )
    }

    // MARK: - CompareSheet variant row

    func test_variantRow_idle() {
        assertDiscoverSnapshot(
            VariantRow(
                row: fixtureRow(),
                accent: teal,
                rank: 0,
                subscriptionState: .idle,
                onTap: { },
                onSubscribe: { }
            )
            .frame(width: 390)
        )
    }

    func test_variantRow_subscribed() {
        assertDiscoverSnapshot(
            VariantRow(
                row: fixtureRow(name: "linux", title: "Linux", host: "lemmy.ml"),
                accent: teal,
                rank: 1,
                subscriptionState: .subscribed,
                onTap: { },
                onSubscribe: { }
            )
            .frame(width: 390)
        )
    }

    // MARK: - DiscoverTrendCard

    func test_trendCard_trending() {
        assertDiscoverSnapshot(
            DiscoverTrendCard(row: fixtureRow(), accent: teal, momentum: false, onTap: { }, subscriptionState: .idle, onSubscribe: { })
        )
    }

    func test_trendCard_rising() {
        assertDiscoverSnapshot(
            DiscoverTrendCard(
                row: fixtureRow(name: "selfhosted", title: "Self-Hosted", subs: 18000, week: 2600),
                accent: teal,
                momentum: true,
                onTap: { },
                subscriptionState: .subscribed,
                onSubscribe: { }
            )
        )
    }

    // MARK: - InstanceCard

    func test_instanceCard() {
        assertDiscoverSnapshot(
            InstanceCard(
                instance: InstanceSummary(
                    host: "lemmy.world",
                    communityCount: 10608,
                    totalSubscribers: 5_400_000,
                    totalActiveWeek: 120_000
                ),
                accent: teal,
                onTap: { }
            )
        )
    }

    // MARK: - InstanceRow (Browse-by-instance See-all)

    func test_instanceRow() {
        assertDiscoverSnapshot(
            InstanceRow(
                instance: InstanceSummary(
                    host: "lemmy.world",
                    communityCount: 10608,
                    totalSubscribers: 5_400_000,
                    totalActiveWeek: 120_000
                ),
                accent: teal,
                onTap: { }
            )
            .frame(width: 390)
        )
    }

    // MARK: - PackCard

    func test_packCard() throws {
        let rows = [
            fixtureRow(name: "technology", title: "Technology", url: "https://lemmy.world/c/technology"),
            fixtureRow(name: "programming", title: "Programming", host: "programming.dev", url: "https://programming.dev/c/programming"),
            fixtureRow(name: "selfhosted", title: "Self-Hosted", url: "https://lemmy.world/c/selfhosted"),
            fixtureRow(name: "linux", title: "Linux", host: "lemmy.ml", url: "https://lemmy.ml/c/linux"),
        ]
        let pack = try XCTUnwrap(
            StarterPackCatalog.resolve(
                [StarterPack(
                    id: "tech",
                    title: "Tech Essentials",
                    blurb: "The core technology, programming and self-hosting hubs.",
                    communityUrls: rows.map(\.communityUrl)
                )],
                using: rows
            ).first
        )
        assertDiscoverSnapshot(PackCard(pack: pack, accent: teal, onTap: { }))
    }

    // MARK: - Rendering

    private func assertDiscoverSnapshot(
        _ view: some View,
        testName: String = #function,
        line: UInt = #line
    ) {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let wrapped = view
                .padding(16)
                .background(Color(uiColor: .systemGroupedBackground))
            let host = UIHostingController(rootView: wrapped)
            let size = host.sizeThatFits(in: CGSize(width: 430, height: 2000))
            host.view.frame = CGRect(origin: .zero, size: size)
            assertSnapshot(
                matching: host,
                as: .image(size: size, traits: traits(style)),
                named: style == .dark ? "dark" : "light",
                testName: testName,
                line: line
            )
        }
    }

    private func traits(_ style: UIUserInterfaceStyle) -> UITraitCollection {
        UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: style),
            UITraitCollection(displayScale: 2),
            SnapshotDeterminism.contentSizeTrait,
        ])
    }

    // MARK: - Fixtures

    private func fixtureRow(
        id: Int64 = 1,
        name: String = "technology",
        title: String? = "Technology",
        host: String = "lemmy.world",
        subs: Int64 = 312_000,
        week: Int64 = 8400,
        alsoOn: Int = 0,
        groupSubs: Int64 = 0,
        nsfw: Bool = false,
        url: String? = nil
    ) -> CommunityListRow {
        CommunityListRow(
            id: id,
            communityUrl: url ?? "https://\(host)/c/\(name)",
            instanceHost: host,
            name: name,
            title: title,
            descriptionText: nil,
            iconUrl: nil,
            isNsfw: nsfw,
            isSuspicious: false,
            numberOfSubscribers: subs,
            numberOfPosts: 0,
            numberOfComments: 0,
            usersActiveWeek: week,
            usersActiveMonth: 0,
            score: 0,
            alsoOnServerCount: alsoOn,
            groupTotalSubscribers: groupSubs
        )
    }
}
