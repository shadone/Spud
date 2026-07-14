//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import SpudDataKit
import SpudUIKit
import SpudUtilKit
import UIKit
import XCTest
@testable import Spud

/// Snapshots of `SearchCommunityCell`'s meta-community badge: a "!announcements@lemmy.world"
/// result (classified meta via `MetaCommunityClassifier`'s instance-identity match on the
/// "lemmy" domain label) shows the `building.2.fill` glyph next to the name, while an ordinary
/// "!photography@lemmy.world" result shows none — each in light and dark. This is the same
/// glyph/tint as the SwiftUI `MetaCommunityBadge` (Discover / Communities tab), rendered here
/// as a plain `UIImageView` because `SearchCommunityCell` is UIKit.
///
/// The cell is built straight from a `SearchCommunityResult` fixture with no icon URL (no
/// async image loading) and rendered at a fixed feed width and pinned display scale, mirroring
/// `SearchResultCellsSnapshotTests`' community coverage.
@MainActor
final class SearchCommunityCellSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        SnapshotDeterminism.pinAccent()
    }

    private let lemmyTeal = UIColor(red: 0, green: 0x96 / 255, blue: 0x87 / 255, alpha: 1)
    private let width: CGFloat = 390

    func test_metaCommunity_showsBadge() async {
        let cell = SearchCommunityCell(style: .default, reuseIdentifier: nil)
        await configure(cell, name: "announcements", qualifiedName: "!announcements@lemmy.world")
        assertCell(cell)
    }

    func test_ordinaryCommunity_noBadge() async {
        let cell = SearchCommunityCell(style: .default, reuseIdentifier: nil)
        await configure(cell, name: "photography", qualifiedName: "!photography@lemmy.world")
        assertCell(cell)
    }

    // MARK: - Configuration

    private func configure(
        _ cell: SearchCommunityCell,
        name: String,
        qualifiedName: String
    ) async {
        cell.configure(
            with: SearchCommunityResult(
                serverCommunityId: 1,
                name: name,
                qualifiedName: qualifiedName,
                instance: instance("https://lemmy.world"),
                subscribersText: "48.2K",
                iconUrl: nil,
                followState: .notFollowing,
                isNsfw: false,
                communityUrl: "https://lemmy.world/c/\(name)"
            ),
            imageService: StaticImageService()
        )
        // `configure` no longer paints the subscribe button (the VC resolves and
        // applies the real 5-state separately) -- apply it here to match the
        // "not subscribed" state the fixture's `followState: .notFollowing` used
        // to derive, mirroring `SearchResultCellsSnapshotTests`.
        cell.applySubscribedState(.notSubscribed)
        await settle()
    }

    // MARK: - Rendering

    /// Pin the accent + an opaque backdrop on the snapshot root. The `.image`
    /// strategy reparents `contentView` into a fresh window, so without its own
    /// tintColor the cell would inherit the window's system blue, and without an
    /// opaque background `label`-colored text would vanish on transparency in
    /// dark mode.
    private func prepare(_ cell: UITableViewCell) {
        cell.tintColor = lemmyTeal
        cell.contentView.tintColor = lemmyTeal
        cell.contentView.backgroundColor = .systemBackground
    }

    private func assertCell(
        _ cell: UITableViewCell,
        testName: String = #function,
        line: UInt = #line
    ) {
        prepare(cell)
        for style in [UIUserInterfaceStyle.light, .dark] {
            cell.frame = CGRect(x: 0, y: 0, width: width, height: 2000)
            cell.layoutIfNeeded()
            let height = cell.contentView.systemLayoutSizeFitting(
                CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            ).height

            // Host the whole cell (not just contentView) on an opaque backdrop so
            // dark-mode text stays legible.
            let container = UIView(frame: CGRect(x: 0, y: 0, width: width, height: height))
            container.backgroundColor = .systemBackground
            container.tintColor = lemmyTeal
            cell.frame = container.bounds
            container.addSubview(cell)
            container.layoutIfNeeded()

            assertSnapshot(
                matching: container,
                as: .image(size: CGSize(width: width, height: height), traits: traits(style)),
                named: style == .dark ? "dark" : "light",
                testName: testName,
                line: line
            )
        }
    }

    /// Let the cell's icon-load Task drain its stream (no-op here -- the fixture
    /// has no icon URL) and apply the resulting layout before we measure and snapshot.
    private func settle() async {
        try? await Task.sleep(nanoseconds: 80_000_000)
        await Task.yield()
    }

    private func traits(_ style: UIUserInterfaceStyle) -> UITraitCollection {
        UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: style),
            UITraitCollection(displayScale: 2),
            SnapshotDeterminism.contentSizeTrait,
        ])
    }

    private func instance(_ urlString: String) -> InstanceActorId {
        InstanceActorId(from: urlString)!
    }
}
