//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import Testing
import UIKit
@testable import Spud

/// Covers the feed's spoken content-status words (removed / deleted /
/// unavailable / pinned / locked) in `PostListPostViewModel.accessibilityLabel`.
/// These must be sourced from the shared `PostStatusBadge.label` factory (the
/// same one driving the post-detail header and the feed's own visible glyph
/// loop) rather than duplicated literals, so every glyph the feed renders also
/// gets announced.
@MainActor
struct PostListPostViewModelStatusAccessibilityTests {
    private func viewModel(
        isRemoved: Bool = false,
        isLocked: Bool = false,
        isFeaturedCommunity: Bool = false,
        isFeaturedLocal: Bool = false,
        isDeleted: Bool = false,
        isUnavailable: Bool = false
    ) -> PostListPostViewModel {
        let row = PostListRow(
            id: 1,
            serverPostId: 1,
            title: "t",
            body: nil,
            originalPostUrl: "https://lemmy.world/post/1",
            url: nil,
            thumbnailUrl: nil,
            urlEmbedTitle: nil,
            urlEmbedDescription: nil,
            altText: nil,
            communityName: "news",
            communityActorId: "https://lemmy.world/c/news",
            serverCommunityId: 1,
            creatorPersonId: 1,
            creatorName: "alice",
            creatorActorId: "https://lemmy.world/u/alice",
            score: 1,
            numberOfComments: 0,
            voteStatus: nil,
            isRead: false,
            isSaved: false,
            isRemoved: isRemoved,
            isLocked: isLocked,
            isFeaturedCommunity: isFeaturedCommunity,
            isFeaturedLocal: isFeaturedLocal,
            isDeleted: isDeleted,
            isUnavailable: isUnavailable,
            isNsfw: false,
            isCreatorModerator: false,
            isCreatorAdmin: false,
            isCreatorBannedFromCommunity: false,
            isCreatorSiteBanned: false,
            isCreatorBot: false,
            isCreatorAccountDeleted: false,
            published: Date(timeIntervalSince1970: 0)
        )
        return PostListPostViewModel(
            row: row,
            appearance: AppearanceService(preferencesService: PreferencesService.ephemeral()),
            postContentDetector: PostContentDetectorService()
        )
    }

    @Test
    func lockedRow_announcesLocked() {
        #expect(viewModel(isLocked: true).accessibilityLabel.contains("Locked"))
    }

    @Test
    func featuredRow_announcesPinned() {
        #expect(viewModel(isFeaturedCommunity: true).accessibilityLabel.contains("Pinned"))
        #expect(viewModel(isFeaturedLocal: true).accessibilityLabel.contains("Pinned"))
    }

    /// The new behavior: previously the feed VM never spoke removed / deleted /
    /// unavailable at all, even though it renders a glyph for each.
    @Test
    func removedRow_announcesRemoved() {
        #expect(viewModel(isRemoved: true).accessibilityLabel.contains("Removed"))
    }

    @Test
    func deletedRow_announcesDeleted() {
        #expect(viewModel(isDeleted: true).accessibilityLabel.contains("Deleted"))
    }

    @Test
    func unavailableRow_announcesUnavailable() {
        #expect(viewModel(isUnavailable: true).accessibilityLabel.contains("Unavailable"))
    }

    /// Ties the assertion to the shared source rather than a duplicated
    /// literal: the spoken word for each status must equal the corresponding
    /// `PostStatusBadge.label`, in the same badge-priority order the visible
    /// glyph loop uses.
    @Test
    func spokenStatusWords_matchSharedBadgeFactory() {
        let cases: [(isRemoved: Bool, isDeleted: Bool, isUnavailable: Bool, isLocked: Bool, isFeatured: Bool)] = [
            (true, false, false, false, false),
            (false, true, false, false, false),
            (false, false, true, false, false),
            (false, false, false, true, false),
            (false, false, false, false, true),
            (false, false, false, true, true),
        ]
        for testCase in cases {
            let vm = viewModel(
                isRemoved: testCase.isRemoved,
                isLocked: testCase.isLocked,
                isFeaturedCommunity: testCase.isFeatured,
                isDeleted: testCase.isDeleted,
                isUnavailable: testCase.isUnavailable
            )
            let expectedBadgeWords = PostStatusBadge.badges(
                isRemoved: testCase.isRemoved,
                isDeleted: testCase.isDeleted,
                isUnavailable: testCase.isUnavailable,
                isLocked: testCase.isLocked,
                isFeatured: testCase.isFeatured
            ).map(\.label)
            for word in expectedBadgeWords {
                #expect(vm.accessibilityLabel.contains(word))
            }
        }
    }
}
