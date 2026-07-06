//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Hosts the feed's full empty / error state (a `UIContentUnavailableView` built
/// from a `UIContentUnavailableConfiguration`) as the table's `backgroundView`,
/// insetting it below any scrolling header so it centers within the region the
/// user actually sees rather than the full table bounds.
///
/// WHY this exists instead of the view-controller-level
/// `contentUnavailableConfiguration`: that overlay renders a transparent
/// content-unavailable view across the WHOLE view, INCLUDING a scrolling header
/// hosted as the table's `tableHeaderView` (the community header), so the error
/// copy ("Couldn't reach <host>" + Try again / Work offline) rendered see-through
/// ON TOP of the header. Rendering into the table's `backgroundView` puts the
/// surface BELOW the header in z-order; `topInset` (the header's height) then
/// centers the content within the below-header region.
///
/// Mirrors the same-bug fix in `PersonViewController.updateContentUnavailable`
/// (commit b7ecc4ce), which renders into `backgroundView`. This variant
/// additionally top-insets by the header height — Person accepted a
/// bounds-centered residual that hides the surface under a taller-than-half
/// header; the feed does better. The inset mirrors the loading skeleton's own
/// `topInset` concept (`FeedLoadingSkeletonView` / `syncSkeletonHeaderInset`), so
/// the skeleton and this surface align below the same header.
final class FeedStateSurfaceView: UIView {
    private var contentView: UIView?
    private var contentTopConstraint: NSLayoutConstraint?

    /// Height reserved at the top for a scrolling header, so the hosted surface
    /// centers below it. Zero for a header-less (plain) feed, which then centers
    /// within the full bounds exactly as before.
    var topInset: CGFloat = 0 {
        didSet { contentTopConstraint?.constant = topInset }
    }

    /// Installs `content` (a `UIContentUnavailableView` from
    /// `config.makeContentView()`), replacing any previous surface. The content is
    /// pinned to the container's edges except the top, which sits at `topInset`.
    func setContentView(_ content: UIView) {
        contentView?.removeFromSuperview()

        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        let top = content.topAnchor.constraint(equalTo: topAnchor, constant: topInset)
        NSLayoutConstraint.activate([
            top,
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        contentView = content
        contentTopConstraint = top
    }
}
