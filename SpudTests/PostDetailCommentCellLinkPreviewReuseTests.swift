//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import Testing
import UIKit
@testable import Spud

/// Regression coverage for comment link-preview cards flickering on every
/// reconfigure.
///
/// Collapsing a comment thread (or voting) reconfigures the header and ALL
/// visible comment cells in place via `applySnapshot`. A reconfigure with
/// unchanged content must not tear down and rebuild the link-preview cards:
/// rebuilding repaints them and re-fetches each embed, which reads as a flash
/// in every neighboring comment. Mirrors `PostDetailHeaderCell`'s
/// `configuredLinkPreviews` guard (see `PostDetailHeaderImageReuseTests`).
@MainActor
struct PostDetailCommentCellLinkPreviewReuseTests {
    private let width: CGFloat = 390

    /// A comment body carrying a previewable bare URL, so the cell builds one
    /// link-preview card below the text.
    private let bodyWithLink = "Great read: https://example.com/research/findings"

    @Test
    func reconfigureWithUnchangedLinks_keepsLinkPreviewCards() {
        let imageService = StaticImageService()
        let cell = PostDetailCommentCell(style: .default, reuseIdentifier: nil)

        cell.configure(with: makeViewModel(voteStatus: nil), imageService: imageService)
        cell.frame = CGRect(x: 0, y: 0, width: width, height: 2000)
        cell.layoutIfNeeded()

        let card = cell.linkPreviewsStackView.arrangedSubviews.first
        #expect(card != nil, "Link-preview card was never built on first configure")

        // An optimistic vote (or a neighboring comment's collapse) reconfigures
        // this cell with the same links; the card must NOT be torn down and
        // rebuilt (which flickers and re-fetches its embed).
        cell.configure(with: makeViewModel(voteStatus: 1), imageService: imageService)
        #expect(
            cell.linkPreviewsStackView.arrangedSubviews.first === card,
            "Reconfiguring with unchanged links rebuilt the link-preview card (flicker + redundant embed fetch)"
        )
    }

    @Test
    func collapseThenExpand_clearsAndRebuildsCards() {
        let imageService = StaticImageService()
        let cell = PostDetailCommentCell(style: .default, reuseIdentifier: nil)

        cell.configure(with: makeViewModel(voteStatus: nil), imageService: imageService)
        #expect(!cell.linkPreviewsStackView.arrangedSubviews.isEmpty)

        // Collapsing hides the body, so the cards must clear with it.
        cell.configure(with: makeViewModel(voteStatus: nil, isCollapsed: true), imageService: imageService)
        #expect(
            cell.linkPreviewsStackView.arrangedSubviews.isEmpty,
            "Collapsing the comment must clear its link-preview cards"
        )

        // Expanding again re-shows the body; the (unchanged) links must rebuild
        // their cards — the skip-guard must not treat the cleared state as built.
        cell.configure(with: makeViewModel(voteStatus: nil), imageService: imageService)
        #expect(
            !cell.linkPreviewsStackView.arrangedSubviews.isEmpty,
            "Expanding the comment must rebuild its link-preview cards"
        )
    }

    // MARK: - Harness

    private func makeViewModel(voteStatus: Int64?, isCollapsed: Bool = false) -> PostDetailCommentViewModel {
        let appearance = AppearanceService(preferencesService: PreferencesService.ephemeral())
        return PostDetailCommentViewModel(
            row: row(voteStatus: voteStatus),
            appearance: appearance,
            isCollapsed: isCollapsed
        )
    }

    private func row(voteStatus: Int64?) -> PostDetailCommentRow {
        PostDetailCommentRow(
            id: 1,
            position: 1,
            depth: 1,
            serverCommentId: 1,
            body: bodyWithLink,
            originalCommentUrl: "https://lemmy.world/comment/1",
            score: 128,
            voteStatus: voteStatus,
            isSaved: false,
            isRemoved: false,
            isDistinguished: false,
            isDeleted: false,
            isCreatorModerator: false,
            isCreatorAdmin: false,
            isCreatorBannedFromCommunity: false,
            isCreatorBlocked: false,
            isCreatorSiteBanned: false,
            isCreatorBot: false,
            isCreatorAccountDeleted: false,
            removedReason: nil,
            published: Date(timeIntervalSinceNow: -3 * 3600),
            creatorName: "ansel",
            creatorPersonId: 1,
            creatorActorId: "https://lemmy.world",
            moreChildCount: nil,
            moreParentId: nil,
            childCount: nil
        )
    }
}
