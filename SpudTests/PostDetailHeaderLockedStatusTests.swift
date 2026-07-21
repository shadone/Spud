//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import Testing
import UIKit
@testable import Spud

/// Covers the post-detail header's locked-post surfacing at the accessibility/
/// VM layer, which the pixel snapshot in
/// `SpudSnapshotTests/PostDetailHeaderSnapshotTests` cannot assert on:
/// - `PostDetailHeaderViewModel.isLocked` / `.contentStatusBadges` for a locked
///   vs. an unlocked row.
/// - The metadata line's VoiceOver label announces a spoken word for EVERY
///   content-status glyph it shows (locked, featured, ...), not just locked.
/// - `LockedCommentsNoticeView`'s combined accessibility element.
@MainActor
struct PostDetailHeaderLockedStatusTests {
    private func viewModel(
        isLocked: Bool = false,
        isFeaturedCommunity: Bool = false,
        isFeaturedLocal: Bool = false
    ) -> PostDetailHeaderViewModel {
        let row = PostDetailHeaderRow(
            id: 1,
            serverPostId: 1,
            title: "t",
            body: nil,
            originalPostUrl: "https://lemmy.world/post/1",
            url: nil,
            thumbnailUrl: nil,
            imageWidth: nil,
            imageHeight: nil,
            urlEmbedTitle: nil,
            urlEmbedDescription: nil,
            altText: nil,
            communityName: "news",
            communityTitle: "News",
            communityActorId: "https://lemmy.world/c/news",
            serverCommunityId: 1,
            creatorName: "Tony",
            creatorPersonId: 1,
            creatorActorId: "https://beehaw.org/u/Tony",
            score: 0,
            numberOfComments: 0,
            voteStatus: nil,
            isSaved: false,
            isRemoved: false,
            isLocked: isLocked,
            isFeaturedCommunity: isFeaturedCommunity,
            isFeaturedLocal: isFeaturedLocal,
            isDeleted: false,
            isNsfw: false,
            isCreatorModerator: false,
            isCreatorAdmin: false,
            isCreatorBannedFromCommunity: false,
            isCreatorSiteBanned: false,
            isCreatorBot: false,
            isCreatorAccountDeleted: false,
            published: Date(timeIntervalSince1970: 0)
        )
        return PostDetailHeaderViewModel(
            row: row,
            appearance: AppearanceService(preferencesService: PreferencesService.ephemeral()),
            postContentDetector: PostContentDetectorService()
        )
    }

    // MARK: - isLocked / contentStatusBadges

    @Test
    func lockedRow_exposesIsLockedTrueAndLockBadge() {
        let vm = viewModel(isLocked: true)
        #expect(vm.isLocked)
        #expect(vm.contentStatusBadges.contains { $0.symbolName == "lock.fill" && $0.color == .systemYellow })
    }

    @Test
    func unlockedRow_exposesIsLockedFalseAndNoLockBadge() {
        let vm = viewModel(isLocked: false)
        #expect(!vm.isLocked)
        #expect(!vm.contentStatusBadges.contains { $0.symbolName == "lock.fill" })
    }

    // MARK: - Metadata-line VoiceOver label

    @Test
    func lockedRow_metadataAccessibilityLabelContainsLockedWord() {
        let vm = viewModel(isLocked: true)
        #expect(vm.subtitleAgeAccessibilityLabel.contains(CommentLockPolicy.shortStatus))
    }

    @Test
    func unlockedRow_metadataAccessibilityLabelOmitsLockedWord() {
        let vm = viewModel(isLocked: false)
        #expect(!vm.subtitleAgeAccessibilityLabel.contains(CommentLockPolicy.shortStatus))
    }

    /// Fix 2: every content-status glyph the header shows must have a spoken
    /// word appended, not only "Locked" — asserted generically over whatever
    /// `contentStatusBadges` renders, so this stays correct as new badge kinds
    /// are added to `PostStatusBadge`.
    @Test
    func lockedRow_metadataAccessibilityLabelAnnouncesEveryShownBadge() {
        let vm = viewModel(isLocked: true)
        #expect(!vm.contentStatusBadges.isEmpty)
        for badge in vm.contentStatusBadges {
            #expect(vm.subtitleAgeAccessibilityLabel.contains(badge.label))
        }
    }

    @Test
    func featuredRow_metadataAccessibilityLabelAnnouncesPinnedWord() {
        let vm = viewModel(isFeaturedCommunity: true)
        #expect(!vm.contentStatusBadges.isEmpty)
        #expect(vm.subtitleAgeAccessibilityLabel.contains("Pinned"))
        for badge in vm.contentStatusBadges {
            #expect(vm.subtitleAgeAccessibilityLabel.contains(badge.label))
        }
    }

    // MARK: - LockedCommentsNoticeView

    @Test
    func noticeView_exposesCombinedStaticTextAccessibilityElement() {
        let view = LockedCommentsNoticeView()
        #expect(view.isAccessibilityElement)
        #expect(view.accessibilityTraits == .staticText)
        #expect(view.accessibilityLabel == "\(CommentLockPolicy.title). \(CommentLockPolicy.message)")
    }
}
