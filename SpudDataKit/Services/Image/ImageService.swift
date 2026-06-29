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
    private let prefetcher: ImagePrefetcher
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
        prefetcher = ImagePrefetcher(pipeline: pipeline, destination: .memoryCache)
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
        let request = ImageRequest(url: url)
        // Full image already decoded in memory: deliver it immediately. Besides
        // the instant paint, this avoids a lost-terminal-event race where
        // imageTask(with:) completes synchronously on a cache hit before the
        // consumer subscribes to .events (Nuke does not replay .finished to a
        // late subscriber).
        if let cached = pipeline.cache[request]?.image {
            recordImageSize(cached.size, for: url)
            return AsyncStream { continuation in
                continuation.yield(.ready(cached))
                continuation.finish()
            }
        }
        let seeded = thumbnailUrl.flatMap { cachedThumbnail(for: $0) }
        return makeProgressiveStream(for: request, url: url, initialThumbnail: seeded)
    }

    /// The downsample point-size the feed warms thumbnails at, and therefore the
    /// cache-key variant a thumbnail is stored under once a post list (or the
    /// offline downloader) has fetched it. Exposed as the single source of truth
    /// so the post list, the prefetcher, the offline downloader, and the
    /// thumbnail-seed probe below all key the same cache entry. A scalar drives a
    /// square `CGSize` because feed thumbnails are square-bounded (`aspectFit`).
    public static let feedThumbnailPointSize = CGSize(width: 64, height: 64)

    /// Returns a thumbnail for `thumbnailUrl` already decoded in the memory
    /// cache, if any, for an instant first paint while the full image loads.
    ///
    /// Probes two cache keys, because a thumbnail can be cached under either:
    ///   1. the bare `ImageRequest(url:)` — e.g. a progressive-decode preview, or
    ///      a thumbnail another surface fetched at full size;
    ///   2. the downsampled feed key (`downsampleRequest`) — what the post list
    ///      cell and the offline downloader actually warm. This is the common
    ///      path: the user taps a post whose thumbnail the list already showed.
    ///
    /// Before this probed the downsampled key, the post-detail header (and the
    /// media viewer) missed the list's cached thumbnail entirely — the list keys
    /// its thumbnail with a `Resize` processor, the header looked it up bare — so
    /// the header showed a gray spinner box (or, offline, the hard failure plate)
    /// even though the decoded thumbnail was sitting in the cache.
    private func cachedThumbnail(for thumbnailUrl: URL) -> UIImage? {
        if let bare = pipeline.cache[ImageRequest(url: thumbnailUrl)]?.image {
            return bare
        }
        let downsampleRequest = Self.downsampleRequest(
            url: thumbnailUrl,
            pointSize: Self.feedThumbnailPointSize
        )
        return pipeline.cache[downsampleRequest]?.image
    }

    /// Drives a Nuke `ImageTask` to the `AsyncStream` event model, surfacing
    /// progressive-decode previews as `.loading(thumbnail:)` so the viewer and
    /// post-detail header paint coarse->sharp before the full image arrives.
    /// Non-progressive sources emit no previews and fall through to `.ready`.
    private func makeProgressiveStream(
        for request: ImageRequest,
        url: URL,
        initialThumbnail: UIImage?
    ) -> AsyncStream<ImageLoadingState> {
        AsyncStream { continuation in
            let imageTask = pipeline.imageTask(with: request)
            let consumer = Task { [weak self] in
                guard let self else { continuation.finish()
                    return
                }
                continuation.yield(.loading(thumbnail: initialThumbnail))
                let signpost = signposter.beginInterval("fetchFull")
                defer { signposter.endInterval("fetchFull", signpost) }
                for await event in imageTask.events {
                    if Task.isCancelled { break }
                    switch event {
                    case let .preview(response):
                        continuation.yield(.loading(thumbnail: response.image))
                    case let .finished(.success(response)):
                        recordImageSize(response.image.size, for: url)
                        continuation.yield(.ready(response.image))
                    case let .finished(.failure(error)):
                        if Task.isCancelled || error.isImageLoadingCancellation { break }
                        alertService.image(error: ImageService.imageLoadingError(from: error), for: url)
                        continuation.yield(.failure)
                    case .started, .progress:
                        break
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                imageTask.cancel()
                consumer.cancel()
            }
        }
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

    /// The Nuke request the feed uses for a downsampled thumbnail. Single source
    /// of truth so prefetch warms exactly the cache entry the cell later reads.
    static func downsampleRequest(url: URL, pointSize: CGSize) -> ImageRequest {
        ImageRequest(
            url: url,
            processors: [ImageProcessors.Resize(size: pointSize, unit: .points, contentMode: .aspectFit)]
        )
    }

    public func fetch(_ url: URL, downsampleTo pointSize: CGSize) -> AsyncStream<ImageLoadingState> {
        let request = Self.downsampleRequest(url: url, pointSize: pointSize)
        return makeStream(for: request, url: url, signpostName: "fetchDownsample")
    }

    public func startPrefetching(_ urls: [URL], downsampleTo pointSize: CGSize) {
        let requests = urls.map { Self.downsampleRequest(url: $0, pointSize: pointSize) }
        prefetcher.startPrefetching(with: requests)
    }

    public func stopPrefetching(_ urls: [URL], downsampleTo pointSize: CGSize) {
        let requests = urls.map { Self.downsampleRequest(url: $0, pointSize: pointSize) }
        prefetcher.stopPrefetching(with: requests)
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
