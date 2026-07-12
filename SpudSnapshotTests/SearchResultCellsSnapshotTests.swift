//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import SpudDataKit
import SpudUtilKit
import UIKit
import XCTest
@testable import Spud

/// Snapshots of the four Search result cells — post, community, user, and
/// comment — across their loaded and missing-image variants, each in light and
/// dark.
///
/// Each cell is built straight from its result fixture and rendered at a fixed
/// feed width and pinned display scale, so the references are device-independent.
/// Loaded image/icon/avatar variants drive the cell with `StaticImageService`
/// (a bundled placeholder image, no network); the missing variants leave the
/// image URL nil so the cell shows its built-in glyph placeholder (or hides the
/// thumbnail, for posts) with no async loading at all.
@MainActor
final class SearchResultCellsSnapshotTests: XCTestCase {
    private let lemmyTeal = UIColor(red: 0, green: 0x96 / 255, blue: 0x87 / 255, alpha: 1)
    private let width: CGFloat = 390

    // MARK: - Post cell

    func test_post_withThumbnail() async {
        let cell = SearchPostCell(style: .default, reuseIdentifier: nil)
        await configurePostCell(cell, thumbnailUrl: URL(string: "https://lemmy.world/pictrs/image/lake.jpg"))
        assertCell(cell)
    }

    func test_post_noThumbnail() async {
        let cell = SearchPostCell(style: .default, reuseIdentifier: nil)
        await configurePostCell(cell, thumbnailUrl: nil)
        assertCell(cell)
    }

    // MARK: - Community cell

    func test_community_withIcon() async {
        let cell = SearchCommunityCell(style: .default, reuseIdentifier: nil)
        await configureCommunityCell(cell, iconUrl: URL(string: "https://lemmy.world/pictrs/image/icon.png"))
        assertCell(cell)
    }

    func test_community_placeholderIcon() async {
        let cell = SearchCommunityCell(style: .default, reuseIdentifier: nil)
        await configureCommunityCell(cell, iconUrl: nil)
        assertCell(cell)
    }

    // MARK: - User cell

    func test_user_withAvatar() async {
        let cell = SearchUserCell(style: .default, reuseIdentifier: nil)
        await configureUserCell(cell, avatarUrl: URL(string: "https://lemmy.world/pictrs/image/avatar.png"))
        assertCell(cell)
    }

    func test_user_placeholderAvatar() async {
        let cell = SearchUserCell(style: .default, reuseIdentifier: nil)
        await configureUserCell(cell, avatarUrl: nil)
        assertCell(cell)
    }

    // MARK: - Comment cell

    func test_comment() async {
        let cell = SearchCommentCell(style: .default, reuseIdentifier: nil)
        cell.configure(with: commentResult())
        await settle()
        assertCell(cell)
    }

    // MARK: - Instance cell

    func test_instance_withIcon() async {
        let cell = SearchInstanceCell(style: .default, reuseIdentifier: nil)
        await configureInstanceCell(cell, iconUrl: "https://programming.dev/pictrs/image/icon.png")
        assertCell(cell)
    }

    func test_instance_placeholderIcon() async {
        let cell = SearchInstanceCell(style: .default, reuseIdentifier: nil)
        await configureInstanceCell(cell, iconUrl: nil)
        assertCell(cell)
    }

    // MARK: - Configuration

    private func configurePostCell(_ cell: SearchPostCell, thumbnailUrl: URL?) async {
        cell.configure(
            with: SearchPostResult(
                serverPostId: 1,
                title: "A scenic mountain lake at golden hour, caught on a hike last weekend",
                communityName: "photography",
                score: 1234,
                numberOfComments: 56,
                published: Date(timeIntervalSinceNow: -5 * 3600),
                thumbnailUrl: thumbnailUrl,
                isNsfw: false
            ),
            imageService: StaticImageService()
        )
        await settle()
    }

    private func configureCommunityCell(_ cell: SearchCommunityCell, iconUrl: URL?) async {
        cell.configure(
            with: SearchCommunityResult(
                serverCommunityId: 1,
                name: "photography",
                qualifiedName: "!photography@lemmy.world",
                instance: instance("https://lemmy.world"),
                subscribersText: "48.2K",
                iconUrl: iconUrl,
                followState: .notFollowing,
                isNsfw: false
            ),
            imageService: StaticImageService()
        )
        await settle()
    }

    private func configureUserCell(_ cell: SearchUserCell, avatarUrl: URL?) async {
        cell.configure(
            with: SearchUserResult(
                serverPersonId: 1,
                name: "Ansel Adams",
                qualifiedName: "@ansel@lemmy.world",
                instance: instance("https://lemmy.world"),
                avatarUrl: avatarUrl
            ),
            imageService: StaticImageService()
        )
        await settle()
    }

    private func configureInstanceCell(_ cell: SearchInstanceCell, iconUrl: String?) async {
        let record = ExplorerInstanceRecord(
            baseurl: "programming.dev",
            name: "Programming.dev",
            usersTotal: 48200,
            iconUrl: iconUrl
        )
        cell.configure(
            with: SearchInstanceResult(record: record),
            imageService: StaticImageService()
        )
        await settle()
    }

    private func commentResult() -> SearchCommentResult {
        SearchCommentResult(
            serverCommentId: 1,
            serverPostId: 1,
            content: "Beautiful light — the golden hour really makes the reflection pop. What lens were you shooting with here?",
            postTitle: "A scenic mountain lake at golden hour",
            creatorName: "dorothea",
            score: 42,
            published: Date(timeIntervalSinceNow: -2 * 3600)
        )
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

            // Host the whole cell (not just contentView) on an opaque backdrop so the
            // disclosure-chevron accessory is captured and dark-mode text stays legible.
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

    /// Let the cell's image-load Task drain its stream and apply the resulting
    /// layout before we measure and snapshot.
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
