//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import UIKit

extension UIViewController {
    /// Presents the full-screen, zoomable media viewer for a single image.
    /// Shared by the post detail, feed, person, and community screens, all of
    /// which surface tappable body images through the markdown renderer.
    /// `MediaViewerViewController.Dependencies` is `HasImageService`; callers
    /// pass their own `dependencies.own`.
    func presentMediaViewer(
        imageUrl: URL,
        thumbnailUrl: URL?,
        preloadedImage: UIImage?,
        altText: String? = nil,
        isNsfw: Bool = false,
        dependencies: MediaViewerViewController.Dependencies
    ) {
        let item = MediaItem(
            imageUrl: imageUrl,
            thumbnailUrl: thumbnailUrl,
            preloadedImage: preloadedImage,
            altText: altText,
            isNsfw: isNsfw
        )
        let viewer = MediaViewerViewController.make(items: [item], dependencies: dependencies)
        FunStats.record(.imagesViewed)
        present(viewer, animated: true)
    }
}
