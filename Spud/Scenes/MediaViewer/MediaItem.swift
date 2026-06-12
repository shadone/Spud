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

    init(imageUrl: URL, thumbnailUrl: URL? = nil, preloadedImage: UIImage? = nil) {
        self.imageUrl = imageUrl
        self.thumbnailUrl = thumbnailUrl
        self.preloadedImage = preloadedImage
    }
}
