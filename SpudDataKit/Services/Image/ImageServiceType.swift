//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

public protocol ImageServiceType: AnyObject, Sendable {
    /// Asynchronously fetch the image at `url`, optionally yielding a thumbnail
    /// while the full image loads.
    ///
    /// The stream emits `.loading(thumbnail:)` first, then either `.ready(image)`
    /// on success or `.failure` on error, and then completes.
    func fetch(_ url: URL, thumbnail thumbnailUrl: URL?) -> AsyncStream<ImageLoadingState>

    /// Fetch an animated image (e.g. GIF) for playback in the full-screen
    /// viewer, yielding a static frame first and then the animated image.
    func fetchAnimatedImage(_ url: URL) -> AsyncStream<ImageLoadingState>
}

public extension ImageServiceType {
    func fetch(_ url: URL) -> AsyncStream<ImageLoadingState> {
        fetch(url, thumbnail: nil)
    }

    /// Default: no animation support — yield the static image. Real
    /// implementations override this to decode and play animated formats.
    func fetchAnimatedImage(_ url: URL) -> AsyncStream<ImageLoadingState> {
        fetch(url, thumbnail: nil)
    }
}

@MainActor
public protocol HasImageService {
    var imageService: ImageServiceType { get }
}
