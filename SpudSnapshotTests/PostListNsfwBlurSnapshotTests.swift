//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import SpudDataKit
import SpudUIKit
import UIKit
import XCTest
@testable import Spud

/// Snapshots of the feed cell `PostListPostCell` for the NSFW blur overlay:
/// blurred (overlay visible) and revealed (overlay hidden after tap).
@MainActor
final class PostListNsfwBlurSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Pin the host scene's status bar hidden so this on-screen
        // (`drawHierarchyInKeyWindow`) capture is immune to an active Simulator
        // GUI session. See `SnapshotDeterminism.pinStatusBarHidden()`.
        SnapshotDeterminism.pinStatusBarHidden()
    }

    private let lemmyTeal = UIColor(red: 0, green: 0x96 / 255, blue: 0x87 / 255, alpha: 1)
    private let width: CGFloat = 390

    // MARK: - Tests

    /// NSFW post with blur enabled and not yet revealed: the overlay should be visible.
    func test_nsfwThumbnail_blurred() async {
        await assertCell(
            nsfwRow(),
            blurNsfw: true,
            isRevealed: false
        )
    }

    /// NSFW post with blur enabled but already revealed: the overlay should be hidden.
    func test_nsfwThumbnail_revealed() async {
        await assertCell(
            nsfwRow(),
            blurNsfw: true,
            isRevealed: true
        )
    }

    // MARK: - Helpers

    private func assertCell(
        _ row: PostListRow,
        blurNsfw: Bool,
        isRevealed: Bool,
        testName: String = #function,
        line: UInt = #line
    ) async {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let cell = await renderCell(
                row: row,
                blurNsfw: blurNsfw,
                isRevealed: isRevealed
            )
            snapshot(cell, style: style, testName: testName, line: line)
        }
    }

    private func renderCell(
        row: PostListRow,
        blurNsfw: Bool,
        isRevealed: Bool
    ) async -> PostListPostCell {
        let cell = PostListPostCell(style: .default, reuseIdentifier: nil)
        cell.tintColor = lemmyTeal
        cell.contentView.tintColor = lemmyTeal
        cell.contentView.backgroundColor = .systemBackground

        cell.configure(
            with: makeViewModel(row: row, blurNsfw: blurNsfw, isRevealed: isRevealed),
            imageService: StaticImageService()
        )
        await settle()

        return cell
    }

    private func snapshot(
        _ cell: PostListPostCell,
        style: UIUserInterfaceStyle,
        testName: String,
        line: UInt
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

    private func makeViewModel(
        row: PostListRow,
        blurNsfw: Bool,
        isRevealed: Bool
    ) -> PostListPostViewModel {
        // A fresh, private UserDefaults suite so the snapshot is independent of
        // whatever preference state a prior test or the sim left behind.
        // `thumbnailPosition`/`showVoteButtons` read their `.left`/`true`
        // defaults from the clean suite.
        let preferences = SnapshotPreferences.ephemeral()
        let appearance = AppearanceService(preferencesService: preferences)
        return PostListPostViewModel(
            row: row,
            appearance: appearance,
            postContentDetector: PostContentDetectorService(),
            blurNsfw: blurNsfw,
            isRevealed: isRevealed
        )
    }

    // MARK: - Fixtures

    private let imageUrl = "https://lemmy.world/pictrs/image/lake.jpg"

    /// An NSFW image post with a thumbnail for the blur overlay to cover.
    private func nsfwRow() -> PostListRow {
        PostListRow(
            id: 1,
            serverPostId: 1,
            title: "[NSFW] Adults-only content",
            body: nil,
            originalPostUrl: "https://lemmy.world/post/1",
            url: imageUrl,
            thumbnailUrl: imageUrl,
            urlEmbedTitle: nil,
            urlEmbedDescription: nil,
            altText: nil,
            communityName: "nsfw",
            communityActorId: "https://lemmy.world/c/nsfw",
            serverCommunityId: 1,
            creatorPersonId: 1,
            creatorName: "alice",
            creatorActorId: "https://lemmy.world/u/alice",
            score: 100,
            numberOfComments: 5,
            voteStatus: nil,
            isRead: false,
            isSaved: false,
            isRemoved: false,
            isLocked: false,
            isFeaturedCommunity: false,
            isFeaturedLocal: false,
            isDeleted: false,
            isNsfw: true,
            published: Date(timeIntervalSinceNow: -2 * 3600)
        )
    }
}
