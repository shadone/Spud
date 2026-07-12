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

/// Snapshots of the Search result cells — post, community, user, comment, instance —
/// across their loaded and missing-image variants, each in light and dark.
///
/// The post cell now renders through the SHARED `PostListPostContentView` (the exact
/// feed rendering), configured with the Search-only view model: the author line on and
/// the vote arrows suppressed. It shows the same rich info as the feed (community@instance,
/// counts, thumbnail, status badges, NSFW blur) plus a `@user@instance` author line.
///
/// The other cells are built straight from their result fixture and rendered at a fixed
/// feed width and pinned display scale, so the references are device-independent. Loaded
/// image variants drive the cell with `StaticImageService` (a bundled placeholder image,
/// no network); the missing variants leave the image URL nil so the cell shows its
/// built-in glyph placeholder (or the text placeholder, for posts) with no async loading.
@MainActor
final class SearchResultCellsSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // The NSFW-blur post render is on-screen (`drawHierarchyInKeyWindow`), so pin the
        // host scene's status bar hidden — immune to an active Simulator GUI session.
        SnapshotDeterminism.pinStatusBarHidden()
    }

    private let lemmyTeal = UIColor(red: 0, green: 0x96 / 255, blue: 0x87 / 255, alpha: 1)
    private let width: CGFloat = 390

    /// A pictrs-style image url whose `.jpg` extension makes the content detector
    /// classify the post as an image.
    private let imageUrl = "https://lemmy.world/pictrs/image/lake.jpg"

    // MARK: - Post cell

    func test_post_withThumbnail() async {
        let cell = SearchPostCell(style: .default, reuseIdentifier: nil)
        cell.postContentView.configure(
            with: makeSearchPostViewModel(row: postRow(imageUrl: imageUrl)),
            imageService: StaticImageService()
        )
        await settle()
        assertCell(cell)
    }

    func test_post_noThumbnail() async {
        let cell = SearchPostCell(style: .default, reuseIdentifier: nil)
        cell.postContentView.configure(
            with: makeSearchPostViewModel(row: postRow(imageUrl: nil)),
            imageService: StaticImageService()
        )
        await settle()
        assertCell(cell)
    }

    /// NSFW search post: it is no longer dropped — it renders blurred through the shared
    /// feed cell. Rendered on-screen so the `UIVisualEffectView` blur is captured.
    func test_post_nsfwBlurred() async {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let cell = SearchPostCell(style: .default, reuseIdentifier: nil)
            cell.tintColor = lemmyTeal
            cell.contentView.tintColor = lemmyTeal
            cell.contentView.backgroundColor = .systemBackground
            cell.postContentView.configure(
                with: makeSearchPostViewModel(
                    row: postRow(imageUrl: imageUrl, isNsfw: true),
                    blurNsfw: true,
                    isRevealed: false
                ),
                imageService: StaticImageService()
            )
            await settle()
            assertCellOnScreen(cell, style: style)
        }
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

    // MARK: - Post configuration

    /// The Search view model for the shared feed cell: author line on, vote arrows off.
    private func makeSearchPostViewModel(
        row: PostListRow,
        blurNsfw: Bool = false,
        isRevealed: Bool = false
    ) -> PostListPostViewModel {
        // A fresh, private UserDefaults suite so the render is independent of any
        // preference state a prior test or the sim left behind.
        let preferences = SnapshotPreferences.ephemeral()
        let appearance = AppearanceService(preferencesService: preferences)
        return PostListPostViewModel(
            row: row,
            appearance: appearance,
            postContentDetector: PostContentDetectorService(),
            blurNsfw: blurNsfw,
            isRevealed: isRevealed,
            showsAuthor: true,
            showVoteButtonsOverride: false
        )
    }

    /// A feed row for a search post. An `imageUrl` makes it an image post (thumbnail
    /// shown); `nil` makes it a text post (placeholder glyph).
    private func postRow(imageUrl: String?, isNsfw: Bool = false) -> PostListRow {
        PostListRow(
            id: 1,
            serverPostId: 1,
            title: "A scenic mountain lake at golden hour, caught on a hike last weekend",
            body: nil,
            originalPostUrl: "https://lemmy.world/post/1",
            url: imageUrl,
            thumbnailUrl: imageUrl,
            urlEmbedTitle: nil,
            urlEmbedDescription: nil,
            altText: nil,
            communityName: "photography",
            communityActorId: "https://lemmy.world/c/photography",
            serverCommunityId: 1,
            creatorPersonId: 1,
            creatorName: "ansel",
            creatorActorId: "https://lemmy.world/u/ansel",
            score: 1234,
            numberOfComments: 56,
            voteStatus: nil,
            isRead: false,
            isSaved: false,
            isRemoved: false,
            isLocked: false,
            isFeaturedCommunity: false,
            isFeaturedLocal: false,
            isDeleted: false,
            isNsfw: isNsfw,
            published: Date(timeIntervalSinceNow: -5 * 3600)
        )
    }

    // MARK: - Other-cell configuration

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

    /// On-screen render (via the key window) so a `UIVisualEffectView` blur is captured
    /// — the default offscreen strategy renders neither the blur nor its glyph.
    private func assertCellOnScreen(
        _ cell: UITableViewCell,
        style: UIUserInterfaceStyle,
        testName: String = #function,
        line: UInt = #line
    ) {
        cell.frame = CGRect(x: 0, y: 0, width: width, height: 2000)
        cell.layoutIfNeeded()
        let height = cell.contentView.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height

        assertSnapshot(
            matching: cell.contentView,
            as: .image(drawHierarchyInKeyWindow: true, size: CGSize(width: width, height: height), traits: traits(style)),
            named: style == .dark ? "dark" : "light",
            testName: testName,
            line: line
        )
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
