//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Nuke
import OSLog
import UIKit

private let logger = Logger.imageService

public final class ImageService: ImageServiceType, @unchecked Sendable {
    /// Decoded pixel sizes of images this service has loaded, keyed by absolute
    /// url. Lets a caller reserve the right amount of space for an image before
    /// it has (re)loaded — e.g. the post-detail header sizing its image
    /// placeholder from the thumbnail the post list already fetched, so the image
    /// doesn't resize the row when it finally appears.
    private let knownSizesLock = NSLock()
    private var knownImageSizes: [String: CGSize] = [:]

    private let pipeline: ImagePipeline
    private let signposter = ImageLoadingSignposter()

    /// Name for this process's on-disk image cache. Each process (app, widget,
    /// extension) gets its own directory; we do not share an App-Group cache
    /// because Nuke's DataCache is not multi-process-write safe.
    private static let diskCacheName = "info.ddenis.Spud.images"

    let alertService: AlertServiceType

    // MARK: Functions

    init(alertService: AlertServiceType, pipeline: ImagePipeline) {
        self.alertService = alertService
        self.pipeline = pipeline
    }

    public convenience init(alertService: AlertServiceType) {
        self.init(
            alertService: alertService,
            pipeline: ImagePipelineFactory.makePipeline(cacheName: Self.diskCacheName)
        )
    }

    public func fetch(
        _ url: URL,
        thumbnail thumbnailUrl: URL?
    ) -> AsyncStream<ImageLoadingState> {
        // Phase 1: seed the loading state with whatever thumbnail Nuke already
        // holds in its memory cache — cheap, synchronous, no network touch.
        // Phase-2 progressive-decode will add incremental previews on top of this.
        let seeded = thumbnailUrl.flatMap { pipeline.cache[ImageRequest(url: $0)]?.image }
        let request = ImageRequest(url: url)
        return makeStream(for: request, url: url, initialThumbnail: seeded, signpostName: "fetchFull")
    }

    /// Fetch and play an animated image (GIF). Yields a loading state while
    /// decoding, then the animated image. Falls back to a static image when
    /// the asset turns out not to be animatable.
    public func fetchAnimatedImage(_ url: URL) -> AsyncStream<ImageLoadingState> {
        AsyncStream { continuation in
            let task = Task { [weak self] in
                guard let self else { continuation.finish()
                    return
                }
                continuation.yield(.loading(thumbnail: nil))
                do {
                    let (data, _) = try await signposter.interval("fetchAnimated") {
                        try await self.pipeline.data(for: ImageRequest(url: url))
                    }
                    if Task.isCancelled { continuation.finish()
                        return
                    }
                    if let animated = AnimatedImageDecoder.animatedImage(from: data) {
                        recordImageSize(animated.size, for: url)
                        continuation.yield(.ready(animated))
                    } else if let image = UIImage(data: data) {
                        let decoded = await image.byPreparingForDisplay() ?? image
                        if Task.isCancelled { continuation.finish()
                            return
                        }
                        recordImageSize(decoded.size, for: url)
                        continuation.yield(.ready(decoded))
                    } else {
                        alertService.image(error: .cannotDecode, for: url)
                        continuation.yield(.failure)
                    }
                } catch {
                    if Task.isCancelled || error.isImageLoadingCancellation {
                        continuation.finish()
                        return
                    }
                    let mapped = (error as? ImagePipeline.Error).map(ImageService.imageLoadingError(from:)) ?? .network(error)
                    alertService.image(error: mapped, for: url)
                    continuation.yield(.failure)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Raw bytes for an animated asset, fetched via the pipeline.
    /// Returns nil when the bytes can't be obtained.
    public func animatedImageData(_ url: URL) async -> Data? {
        do {
            let (data, _) = try await pipeline.data(for: ImageRequest(url: url))
            return data
        } catch {
            return nil
        }
    }

    public func fetch(_ url: URL, downsampleTo pointSize: CGSize) -> AsyncStream<ImageLoadingState> {
        let request = ImageRequest(
            url: url,
            processors: [ImageProcessors.Resize(size: pointSize, unit: .points, contentMode: .aspectFit)]
        )
        return makeStream(for: request, url: url, signpostName: "fetchDownsample")
    }

    /// Shared adapter: drives a Nuke request to the `AsyncStream` event model.
    /// Yields `.loading(thumbnail:)` immediately (seeded with `initialThumbnail`
    /// when available), then `.ready` on success or `.failure` on a real error.
    /// A cancelled request exits quietly.
    private func makeStream(
        for request: ImageRequest,
        url: URL,
        initialThumbnail: UIImage? = nil,
        signpostName: StaticString
    ) -> AsyncStream<ImageLoadingState> {
        AsyncStream { continuation in
            let task = Task { [weak self] in
                guard let self else { continuation.finish()
                    return
                }
                continuation.yield(.loading(thumbnail: initialThumbnail))
                do {
                    let image = try await signposter.interval(signpostName) {
                        try await self.pipeline.image(for: request)
                    }
                    if Task.isCancelled { continuation.finish()
                        return
                    }
                    recordImageSize(image.size, for: url)
                    continuation.yield(.ready(image))
                } catch {
                    if Task.isCancelled || error.isImageLoadingCancellation {
                        continuation.finish()
                        return
                    }
                    let mapped = (error as? ImagePipeline.Error).map(ImageService.imageLoadingError(from:)) ?? .network(error)
                    alertService.image(error: mapped, for: url)
                    continuation.yield(.failure)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func imageSize(for url: URL) -> CGSize? {
        knownSizesLock.lock()
        defer { knownSizesLock.unlock() }
        return knownImageSizes[url.absoluteString]
    }

    /// Records the decoded size of an image so callers can later reserve space
    /// for it at the right aspect ratio. Downsampled images preserve the
    /// original aspect ratio, so recording their (smaller) size is enough.
    private func recordImageSize(_ size: CGSize, for url: URL) {
        guard size.width > 0, size.height > 0 else { return }
        knownSizesLock.lock()
        knownImageSizes[url.absoluteString] = size
        knownSizesLock.unlock()
    }
}

extension Error {
    /// Whether this error represents a cancelled image request rather than a real
    /// transport failure: a Swift task cancellation, `URLError.cancelled`
    /// (`NSURLErrorCancelled`, -999), `ImagePipeline.Error.cancelled`, or any of
    /// those wrapped in `ImageLoadingError.network`.
    var isImageLoadingCancellation: Bool {
        if self is CancellationError { return true }
        if (self as? URLError)?.code == .cancelled { return true }
        if let nukeError = self as? ImagePipeline.Error, case .cancelled = nukeError { return true }
        if let imageError = self as? ImageLoadingError, case let .network(underlying) = imageError {
            return underlying.isImageLoadingCancellation
        }
        return false
    }
}

extension ImageService {
    /// Maps a Nuke pipeline error onto the app's `ImageLoadingError` so callers
    /// (and `AlertService`) see the same error vocabulary they did before Nuke.
    static func imageLoadingError(from nukeError: ImagePipeline.Error) -> ImageLoadingError {
        switch nukeError {
        case let .dataLoadingFailed(error):
            return .network(error)
        case .decodingFailed, .decoderNotRegistered, .dataIsEmpty:
            return .cannotDecode
        default:
            return .network(nukeError)
        }
    }
}
