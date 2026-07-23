//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import UIKit

extension UIViewController {
    /// Presents the full-screen, zoomable media viewer for a single image.
    /// Shared by the post detail, feed, person, community, and activity screens.
    /// `MediaViewerViewController.Dependencies` is `HasImageService`; callers
    /// pass their own `dependencies.own`.
    ///
    /// `zoomSource`, when provided, opts the presentation into the iOS 18 zoom
    /// transition: the viewer expands from, and shrinks back into, the view the
    /// closure returns. The closure is re-invoked on present *and* dismiss, so it
    /// must re-resolve the live on-screen source view by a stable identifier
    /// rather than capture a `UIView` (reused cells move). Returning `nil` (the
    /// source scrolled off / was recycled) falls back to a plain cross-dissolve
    /// instead of animating from a stale frame.
    func presentMediaViewer(
        imageUrl: URL,
        thumbnailUrl: URL?,
        preloadedImage: UIImage?,
        altText: String? = nil,
        isNsfw: Bool = false,
        dependencies: MediaViewerViewController.Dependencies,
        zoomSource: ((MediaItem) -> UIView?)? = nil
    ) {
        let item = MediaItem(
            imageUrl: imageUrl,
            thumbnailUrl: thumbnailUrl,
            preloadedImage: preloadedImage,
            altText: altText,
            isNsfw: isNsfw
        )
        let viewer = MediaViewerViewController.make(
            items: [item],
            dependencies: dependencies,
            zoomSource: zoomSource
        )
        FunStats.record(.imagesViewed)
        present(viewer, animated: true)
    }
}
