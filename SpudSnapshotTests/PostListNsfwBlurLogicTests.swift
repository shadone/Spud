//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SpudUIKit
import UIKit
import XCTest
@testable import Spud

/// Deterministic, render-independent assertions for the NSFW blur overlay logic.
/// These tests do not depend on UIVisualEffectView rendering (which is skipped
/// by the offscreen snapshot context) — they assert the view-model predicate and
/// the cell wiring directly.
@MainActor
final class PostListNsfwBlurLogicTests: XCTestCase {
    // MARK: - isThumbnailBlurred matrix

    func test_isThumbnailBlurred_nsfw_blurEnabled_notRevealed_isTrue() {
        let vm = makeViewModel(isNsfw: true, blurNsfw: true, isRevealed: false)
        XCTAssertTrue(vm.isThumbnailBlurred)
    }

    func test_isThumbnailBlurred_nsfw_blurEnabled_revealed_isFalse() {
        let vm = makeViewModel(isNsfw: true, blurNsfw: true, isRevealed: true)
        XCTAssertFalse(vm.isThumbnailBlurred)
    }

    func test_isThumbnailBlurred_nsfw_blurDisabled_isFalse() {
        let vm = makeViewModel(isNsfw: true, blurNsfw: false, isRevealed: false)
        XCTAssertFalse(vm.isThumbnailBlurred)
    }

    func test_isThumbnailBlurred_notNsfw_blurEnabled_isFalse() {
        let vm = makeViewModel(isNsfw: false, blurNsfw: true, isRevealed: false)
        XCTAssertFalse(vm.isThumbnailBlurred)
    }

    // MARK: - Cell wiring

    func test_cell_isBlurred_whenNsfwAndBlurEnabledAndNotRevealed() {
        let cell = PostListPostCell(style: .default, reuseIdentifier: nil)
        cell.frame = CGRect(x: 0, y: 0, width: 390, height: 200)
        cell.configure(
            with: makeViewModel(isNsfw: true, blurNsfw: true, isRevealed: false),
            imageService: StaticImageService()
        )
        XCTAssertTrue(cell.thumbnailView.isBlurred)
    }

    func test_cell_isNotBlurred_whenRevealed() {
        let cell = PostListPostCell(style: .default, reuseIdentifier: nil)
        cell.frame = CGRect(x: 0, y: 0, width: 390, height: 200)
        cell.configure(
            with: makeViewModel(isNsfw: true, blurNsfw: true, isRevealed: true),
            imageService: StaticImageService()
        )
        XCTAssertFalse(cell.thumbnailView.isBlurred)
    }

    // MARK: - Helpers

    private func makeViewModel(
        isNsfw: Bool,
        blurNsfw: Bool,
        isRevealed: Bool
    ) -> PostListPostViewModel {
        let preferences = PreferencesService()
        preferences.thumbnailPosition = .left
        preferences.showVoteButtons = true
        let appearance = AppearanceService(preferencesService: preferences)
        return PostListPostViewModel(
            row: nsfwRow(isNsfw: isNsfw),
            appearance: appearance,
            postContentDetector: PostContentDetectorService(),
            blurNsfw: blurNsfw,
            isRevealed: isRevealed
        )
    }

    private let imageUrl = "https://lemmy.world/pictrs/image/lake.jpg"

    private func nsfwRow(isNsfw: Bool) -> PostListRow {
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
            isNsfw: isNsfw,
            published: Date(timeIntervalSinceNow: -2 * 3600)
        )
    }
}
