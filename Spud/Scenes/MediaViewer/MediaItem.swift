//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// A single piece of media to show in the full-screen viewer.
///
/// `imageUrl` is the full-resolution asset. `thumbnailUrl` (and the optional
/// `preloadedImage` already held by the originating cell) let the viewer paint
/// something instantly while the full image downloads.
struct MediaItem: Equatable {
    let imageUrl: URL
    let thumbnailUrl: URL?

    /// An image already loaded by the originating view (e.g. the post-detail
    /// header or a list thumbnail), used for an instant first frame.
    let preloadedImage: UIImage?

    /// The image's description (`post.alt_text`), shown as the viewer caption.
    /// nil when the post carries no alt text.
    let altText: String?

    /// True when the full asset is an animated format (GIF) the viewer should
    /// play. Derived from the image URL's extension, mirroring the content
    /// detector.
    let isAnimated: Bool

    /// True when this media belongs to an NSFW post (or community). Drives the
    /// privacy screen that hides the viewer from the app-switcher snapshot and
    /// screen captures.
    let isNsfw: Bool

    init(
        imageUrl: URL,
        thumbnailUrl: URL? = nil,
        preloadedImage: UIImage? = nil,
        altText: String? = nil,
        isNsfw: Bool = false
    ) {
        self.imageUrl = imageUrl
        self.thumbnailUrl = thumbnailUrl
        self.preloadedImage = preloadedImage
        self.altText = altText
        self.isNsfw = isNsfw
        isAnimated = imageUrl.pathExtension.lowercased() == "gif"
    }
}
