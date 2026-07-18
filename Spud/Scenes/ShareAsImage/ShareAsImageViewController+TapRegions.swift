//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudUIKit
import UIKit

/// The editor's direct-manipulation tap-region mapping: it derives the
/// ``ShareAsImageTapOverlayView`` targets from the live preview card's laid-out
/// section frames, so a tap on the drawn card toggles the matching option.
///
/// Extracted from ``ShareAsImageViewController`` (following the
/// `+Output` extension precedent) purely to keep each file single-purpose — the
/// behavior is unchanged. ``updateTapRegions()`` is the only internal entry
/// point (called from the controller's `layoutPreview`); everything else is a
/// private helper of this file.
extension ShareAsImageViewController {
    /// Rebuilds the overlay's tap regions from the current preview card's
    /// section frames. Called after every layout pass.
    func updateTapRegions() {
        if let postCard {
            tapOverlay.setRegions(postRegions(postCard))
        } else if let chainCard {
            tapOverlay.setRegions(chainRegions(chainCard))
        }
    }

    private func rect(of subview: UIView) -> CGRect {
        tapOverlay.convert(subview.bounds, from: subview)
    }

    private func postRegions(_ card: ShareCardView) -> [ShareAsImageTapRegion] {
        var regions: [ShareAsImageTapRegion] = []
        let post = content.post

        // Community lockup (the header area left of the creator) toggles the
        // whole community+creator header; the creator lockup (added AFTER, so it
        // wins where they overlap) toggles redaction.
        let headerRect = rect(of: card.headerView)
        let creatorRect = rect(of: card.headerView.creatorView)
        let communityWidth = max(creatorRect.minX - headerRect.minX, headerRect.width * 0.5)
        regions.append(ShareAsImageTapRegion(
            rect: CGRect(x: headerRect.minX, y: headerRect.minY, width: communityWidth, height: headerRect.height),
            accessibilityLabel: "Community and author",
            accessibilityValue: viewModel.options.showCommunityAndCreator ? "Shown" : "Hidden",
            accessibilityHint: viewModel.options.showCommunityAndCreator ? "Double tap to hide" : "Double tap to show",
            action: { [weak self] in self?.toggle { $0.toggleCommunityAndCreator() } }
        ))
        if post?.creatorHandle != nil {
            regions.append(ShareAsImageTapRegion(
                rect: creatorRect,
                accessibilityLabel: "Author identity",
                accessibilityValue: viewModel.options.redactIdentities ? "Hidden" : "Shown",
                accessibilityHint: viewModel.options.redactIdentities ? "Double tap to show" : "Double tap to hide",
                action: { [weak self] in self?.toggle { $0.toggleRedactIdentities() } }
            ))
        }

        if post?.mediaUrl != nil {
            regions.append(ShareAsImageTapRegion(
                rect: rect(of: card.mediaView),
                accessibilityLabel: "Image",
                accessibilityValue: viewModel.options.showMedia ? "Shown" : "Hidden",
                accessibilityHint: viewModel.options.showMedia ? "Double tap to hide" : "Double tap to show",
                action: { [weak self] in self?.toggle { $0.toggleMedia() } }
            ))
        }

        if post?.bodyPlain != nil {
            regions.append(ShareAsImageTapRegion(
                rect: rect(of: card.bodyView),
                accessibilityLabel: "Body text",
                accessibilityValue: bodyTreatmentDescription,
                accessibilityHint: "Double tap to change how much of the body shows",
                action: { [weak self] in self?.toggle { $0.cycleBodyTreatment() } }
            ))
        }

        regions.append(ShareAsImageTapRegion(
            rect: rect(of: card.statsView),
            accessibilityLabel: "Score and comments",
            accessibilityValue: viewModel.options.showStats ? "Shown" : "Hidden",
            accessibilityHint: viewModel.options.showStats ? "Double tap to hide" : "Double tap to show",
            action: { [weak self] in self?.toggle { $0.toggleStats() } }
        ))

        regions.append(footerRegion(rect: rect(of: card.footerView)))
        return regions
    }

    private func chainRegions(_ card: ShareChainCardView) -> [ShareAsImageTapRegion] {
        var regions: [ShareAsImageTapRegion] = []
        if content.post != nil {
            regions.append(ShareAsImageTapRegion(
                rect: rect(of: card.postHeaderView),
                accessibilityLabel: "Post context",
                accessibilityValue: viewModel.options.includePostInChain ? "Shown" : "Hidden",
                accessibilityHint: viewModel.options.includePostInChain ? "Double tap to hide" : "Double tap to show",
                action: { [weak self] in self?.toggle { $0.toggleIncludePostInChain() } }
            ))
        }
        regions.append(ShareAsImageTapRegion(
            rect: rect(of: card.rowsStack),
            accessibilityLabel: "Comment authors",
            accessibilityValue: viewModel.options.redactIdentities ? "Hidden" : "Shown",
            accessibilityHint: viewModel.options.redactIdentities ? "Double tap to show" : "Double tap to hide",
            action: { [weak self] in self?.toggle { $0.toggleRedactIdentities() } }
        ))
        regions.append(footerRegion(rect: rect(of: card.footerView)))
        return regions
    }

    private func footerRegion(rect: CGRect) -> ShareAsImageTapRegion {
        ShareAsImageTapRegion(
            rect: rect,
            accessibilityLabel: "Spud mark",
            accessibilityValue: viewModel.options.showViaSpudMark ? "Shown" : "Hidden",
            accessibilityHint: viewModel.options.showViaSpudMark ? "Double tap to hide" : "Double tap to show",
            action: { [weak self] in self?.toggle { $0.toggleViaSpudMark() } }
        )
    }

    private var bodyTreatmentDescription: String {
        switch viewModel.options.bodyTreatment {
        case .full: "Showing the full body"
        case .truncate: "Showing a truncated body"
        case .titleOnly: "Hiding the body"
        }
    }

    /// Runs a view-model mutation, then cross-dissolves the preview + fires a
    /// haptic — the shared path for every direct-manipulation tap.
    private func toggle(_ mutate: (ShareAsImageViewModel) -> Void) {
        mutate(viewModel)
        refreshPreview(animated: true)
        Haptics.tap()
    }
}
