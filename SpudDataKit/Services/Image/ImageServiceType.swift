//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreGraphics
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

    /// Fetch the image at `url` downsampled so it fits a `pointSize` display
    /// area, avoiding loading a full-resolution bitmap into a small view.
    func fetch(_ url: URL, downsampleTo pointSize: CGSize) -> AsyncStream<ImageLoadingState>

    /// Raw bytes for an animated asset (GIF), so callers can save or share the
    /// original animation rather than a flattened frame. Returns nil when no
    /// bytes are available.
    func animatedImageData(_ url: URL) async -> Data?

    /// The decoded pixel size of an image this service has already loaded at
    /// `url`, if known. Lets callers reserve layout space at the right aspect
    /// ratio before the image (re)appears. Returns nil when the size isn't known.
    func imageSize(for url: URL) -> CGSize?

    /// Begin low-priority warm-up of feed thumbnails at the given downsample
    /// size, so a cell that scrolls into view finds the decoded image cached.
    func startPrefetching(_ urls: [URL], downsampleTo pointSize: CGSize)

    /// Cancel warm-up started by `startPrefetching` for rows that scrolled out
    /// of the prefetch window.
    func stopPrefetching(_ urls: [URL], downsampleTo pointSize: CGSize)
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

    /// Default: no downsampling — yield the full-resolution image. Real
    /// implementations override this to decode at the target size.
    func fetch(_ url: URL, downsampleTo pointSize: CGSize) -> AsyncStream<ImageLoadingState> {
        fetch(url, thumbnail: nil)
    }

    /// Default: no raw animated bytes available.
    func animatedImageData(_ url: URL) async -> Data? {
        nil
    }

    /// Default: image sizes aren't tracked, so nothing is known ahead of load.
    func imageSize(for url: URL) -> CGSize? {
        nil
    }

    /// Default: no prefetching. Real implementations override this.
    func startPrefetching(_ urls: [URL], downsampleTo pointSize: CGSize) { }

    func stopPrefetching(_ urls: [URL], downsampleTo pointSize: CGSize) { }
}

@MainActor
public protocol HasImageService {
    var imageService: ImageServiceType { get }
}
