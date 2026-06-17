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
    /// In-memory cache for loaded images.
    ///
    /// Each cache entry has associated cost that is the size of the image (width \* height)
    let memoryCache: NSCache<NSURL, UIImage>

    /// Separate cache for decoded animated (GIF) images. Kept apart from
    /// `memoryCache` so a static fetch of the same URL never returns the
    /// multi-frame image (which a `UIImageView` would auto-animate inline).
    let animatedCache: NSCache<NSURL, UIImage>

    /// Cache for downsampled images, keyed by url + target pixel size so the
    /// same url at different display sizes does not collide and a small cell
    /// never gets a full-resolution bitmap.
    let downsampledCache: NSCache<NSString, UIImage>

    /// Raw bytes of fetched animated images, keyed by url. Lets the viewer save
    /// or share the original GIF with its animation intact, rather than the
    /// flattened single frame a decoded `UIImage` would yield.
    let animatedDataCache: NSCache<NSURL, NSData>

    /// Pixel-per-point factor used when converting a requested point size to a
    /// downsample target. Fixed at the maximum modern screen scale so the
    /// result stays crisp on every device without a main-actor scale lookup
    /// from the background fetch task.
    private let downsampleScale: CGFloat = 3

    /// Decoded pixel sizes of images this service has loaded, keyed by absolute
    /// url. Lets a caller reserve the right amount of space for an image before
    /// it has (re)loaded — e.g. the post-detail header sizing its image
    /// placeholder from the thumbnail the post list already fetched, so the image
    /// doesn't resize the row when it finally appears.
    private let knownSizesLock = NSLock()
    private var knownImageSizes: [String: CGSize] = [:]

    let session: URLSession

    let alertService: AlertServiceType

    // MARK: Functions

    public init(alertService: AlertServiceType) {
        self.alertService = alertService

        // Send a plain `Spud/<version>` User-Agent instead of iOS' default,
        // whose `CFNetwork/...` token some Lemmy instances' nginx denylist
        // (returning 403 for every pict-rs / image_proxy url). See AppUserAgent.
        let configuration = URLSessionConfiguration.default
        var headers = configuration.httpAdditionalHeaders ?? [:]
        headers["User-Agent"] = AppUserAgent.value
        configuration.httpAdditionalHeaders = headers
        session = URLSession(configuration: configuration)

        memoryCache = NSCache()
        // There is no science to this limit, only guesswork.
        memoryCache.countLimit = 100
        // Approx 1GB of memory assuming 1 byte per pixel.
        memoryCache.totalCostLimit = 1024 * 1024 * 1024

        animatedCache = NSCache()
        // Animated images hold every frame, so cap the count tightly.
        animatedCache.countLimit = 16
        animatedCache.totalCostLimit = 1024 * 1024 * 1024

        downsampledCache = NSCache()
        downsampledCache.countLimit = 300
        downsampledCache.totalCostLimit = 256 * 1024 * 1024

        animatedDataCache = NSCache()
        animatedDataCache.countLimit = 16
        // Raw GIF bytes can be a few MB each; cap the byte cache at ~256MB.
        animatedDataCache.totalCostLimit = 256 * 1024 * 1024
    }

    public func fetch(
        _ url: URL,
        thumbnail thumbnailUrl: URL?
    ) -> AsyncStream<ImageLoadingState> {
        AsyncStream { continuation in
            let task = Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }

                if let cachedImage = memoryCache.object(forKey: url as NSURL) {
                    continuation.yield(.ready(cachedImage))
                    continuation.finish()
                    return
                }

                let cachedThumbnail = thumbnailUrl.flatMap {
                    self.memoryCache.object(forKey: $0 as NSURL)
                }
                continuation.yield(.loading(thumbnail: cachedThumbnail))

                // When the full image isn't cached and we don't already have a
                // thumbnail in hand, fetch the (smaller, faster) thumbnail
                // concurrently and yield it as a low-res preview the instant it
                // arrives, so the caller can paint something while the full image
                // downloads. The full-image load below cancels this once it wins;
                // a preview that loses the race is yielded after the stream has
                // finished (and so dropped) and is ignored by the consumer.
                let thumbnailTask: Task<Void, Never>?
                if cachedThumbnail == nil, let thumbnailUrl, thumbnailUrl != url {
                    thumbnailTask = Task { [weak self] in
                        guard
                            let self,
                            let thumbnail = try? await loadImage(from: thumbnailUrl),
                            !Task.isCancelled
                        else { return }
                        continuation.yield(.loading(thumbnail: thumbnail))
                    }
                } else {
                    thumbnailTask = nil
                }

                do {
                    let image = try await loadImage(from: url)
                    thumbnailTask?.cancel()
                    if Task.isCancelled {
                        continuation.finish()
                        return
                    }
                    continuation.yield(.ready(image))
                } catch let error as ImageLoadingError {
                    thumbnailTask?.cancel()
                    alertService.image(error: error, for: url)
                    continuation.yield(.failure)
                } catch {
                    thumbnailTask?.cancel()
                    alertService.image(error: .network(error), for: url)
                    continuation.yield(.failure)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Fetch and play an animated image (GIF). Yields the cached static frame
    /// (if any) while decoding, then the animated image. Falls back to a static
    /// image when the asset turns out not to be animatable.
    public func fetchAnimatedImage(_ url: URL) -> AsyncStream<ImageLoadingState> {
        AsyncStream { continuation in
            let task = Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }

                if let cached = animatedCache.object(forKey: url as NSURL) {
                    continuation.yield(.ready(cached))
                    continuation.finish()
                    return
                }

                // A static frame already loaded for the inline thumbnail gives
                // the viewer something to paint while the GIF decodes.
                let staticFrame = memoryCache.object(forKey: url as NSURL)
                continuation.yield(.loading(thumbnail: staticFrame))

                do {
                    let image = try await loadAnimatedImage(from: url)
                    if Task.isCancelled {
                        continuation.finish()
                        return
                    }
                    continuation.yield(.ready(image))
                } catch let error as ImageLoadingError {
                    alertService.image(error: error, for: url)
                    continuation.yield(.failure)
                } catch {
                    alertService.image(error: .network(error), for: url)
                    continuation.yield(.failure)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Raw bytes for an animated asset, preferring the cache populated when the
    /// viewer played it (so save/share is instant and does not re-download).
    /// Falls back to a fetch, and returns nil when the bytes can't be obtained.
    public func animatedImageData(_ url: URL) async -> Data? {
        if let cached = animatedDataCache.object(forKey: url as NSURL) {
            return cached as Data
        }
        guard let bytes = try? await data(from: url) else {
            return nil
        }
        animatedDataCache.setObject(bytes as NSData, forKey: url as NSURL, cost: bytes.count)
        return bytes
    }

    public func fetch(_ url: URL, downsampleTo pointSize: CGSize) -> AsyncStream<ImageLoadingState> {
        let maxPixelSize = max(pointSize.width, pointSize.height) * downsampleScale
        // Capture a Sendable String, not an NSString, into the stream closure.
        let key = "\(url.absoluteString)|\(Int(maxPixelSize.rounded()))"

        return AsyncStream { continuation in
            let task = Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }

                if let cached = downsampledCache.object(forKey: key as NSString) {
                    continuation.yield(.ready(cached))
                    continuation.finish()
                    return
                }

                continuation.yield(.loading(thumbnail: nil))

                do {
                    let image = try await loadDownsampledImage(from: url, maxPixelSize: maxPixelSize, key: key)
                    if Task.isCancelled {
                        continuation.finish()
                        return
                    }
                    continuation.yield(.ready(image))
                } catch {
                    // A cancelled request is expected teardown (the consumer dropped the
                    // stream, so onTermination cancelled this task), not a failure to
                    // surface. Exit quietly without alerting or yielding .failure.
                    if Task.isCancelled || error.isImageLoadingCancellation {
                        continuation.finish()
                        return
                    }
                    let imageError = (error as? ImageLoadingError) ?? .network(error)
                    alertService.image(error: imageError, for: url)
                    continuation.yield(.failure)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Download the bytes at `url`, mapping transport and HTTP failures to
    /// `ImageLoadingError`.
    private func data(from url: URL) async throws -> Data {
        // TODO: check if the image is present in URLSession cache.

        let (data, urlResponse): (Data, URLResponse)
        do {
            (data, urlResponse) = try await session.data(from: url)
        } catch {
            // A cancelled request (URLError.cancelled / -999, or task teardown when a
            // cell scrolls off-screen or a newer fetch supersedes this one) is expected,
            // not a transport failure. Logging it as an error floods the log during normal
            // scrolling and buries genuine failures, so demote it to debug.
            if error.isImageLoadingCancellation {
                logger.debug("Image request cancelled for \(url.absoluteString, privacy: .public)")
            } else {
                logger.error("Image transport error for \(url.absoluteString, privacy: .public): \(String(describing: error), privacy: .public)")
            }
            throw ImageLoadingError.network(error)
        }

        guard let httpUrlResponse = urlResponse as? HTTPURLResponse else {
            logger.error("Image response was not HTTP for \(url.absoluteString, privacy: .public)")
            throw ImageLoadingError.cannotDecode
        }

        let statusCode = httpUrlResponse.statusCode
        guard statusCode == 200 else {
            logFailedResponse(httpUrlResponse, body: data, requestUrl: url)
            throw ImageLoadingError.serverError(statusCode: statusCode)
        }

        return data
    }

    /// Diagnostic dump for a non-200 image response. Logs the request url, the
    /// status, the headers that reveal who answered (Cloudflare edge vs Lemmy vs
    /// pict-rs), and a snippet of the body (a Cloudflare block is HTML; a Lemmy
    /// error is JSON). Intended to identify why proxied image urls are rejected.
    private func logFailedResponse(_ response: HTTPURLResponse, body: Data, requestUrl: URL) {
        func header(_ name: String) -> String {
            (response.value(forHTTPHeaderField: name)) ?? "-"
        }
        let bodySnippet = String(decoding: body.prefix(512), as: UTF8.self)
            .replacingOccurrences(of: "\n", with: " ")
        logger.error(
            """
            Image load failed status=\(response.statusCode, privacy: .public) \
            url=\(requestUrl.absoluteString, privacy: .public)
            server=\(header("Server"), privacy: .public) \
            cf-ray=\(header("CF-Ray"), privacy: .public) \
            cf-mitigated=\(header("cf-mitigated"), privacy: .public) \
            content-type=\(header("Content-Type"), privacy: .public) \
            content-length=\(header("Content-Length"), privacy: .public) \
            retry-after=\(header("Retry-After"), privacy: .public) \
            www-authenticate=\(header("WWW-Authenticate"), privacy: .public)
            body[0..512]=\(bodySnippet, privacy: .public)
            """
        )
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

    private func loadImage(from url: URL) async throws -> UIImage {
        let data = try await data(from: url)

        guard let image = UIImage(data: data) else {
            throw ImageLoadingError.cannotDecode
        }

        // Force the expensive bitmap decode now, on this background task.
        // `UIImage(data:)` decodes lazily on first draw — which, for an image
        // set on a cell during scroll, lands on the main thread and stutters.
        // Decoding here keeps the scroll path hitch-free; fall back to the
        // undecoded image if preparation is unavailable for this format.
        let decodedImage = await image.byPreparingForDisplay() ?? image

        recordImageSize(decodedImage.size, for: url)
        memoryCache.setObject(
            decodedImage,
            forKey: url as NSURL,
            cost: Int(decodedImage.size.width * decodedImage.size.height)
        )

        return decodedImage
    }

    private func loadAnimatedImage(from url: URL) async throws -> UIImage {
        let data = try await data(from: url)

        if let animated = AnimatedImageDecoder.animatedImage(from: data) {
            let frameCount = animated.images?.count ?? 1
            recordImageSize(animated.size, for: url)
            animatedCache.setObject(
                animated,
                forKey: url as NSURL,
                cost: Int(animated.size.width * animated.size.height) * frameCount
            )
            // Keep the original bytes so save/share can preserve the animation.
            animatedDataCache.setObject(data as NSData, forKey: url as NSURL, cost: data.count)
            return animated
        }

        // Single frame (or an undecodable animation): treat it as a still image.
        guard let image = UIImage(data: data) else {
            throw ImageLoadingError.cannotDecode
        }
        let decodedImage = await image.byPreparingForDisplay() ?? image
        recordImageSize(decodedImage.size, for: url)
        memoryCache.setObject(
            decodedImage,
            forKey: url as NSURL,
            cost: Int(decodedImage.size.width * decodedImage.size.height)
        )
        return decodedImage
    }

    private func loadDownsampledImage(
        from url: URL,
        maxPixelSize: CGFloat,
        key: String
    ) async throws -> UIImage {
        let data = try await data(from: url)

        let image: UIImage
        if let downsampled = ImageDownsampler.downsample(data: data, maxPixelSize: maxPixelSize) {
            image = downsampled
        } else if let full = UIImage(data: data) {
            // Undecodable as a thumbnail (e.g. an unusual format): fall back to a
            // full decode so the cell still shows something.
            image = await full.byPreparingForDisplay() ?? full
        } else {
            throw ImageLoadingError.cannotDecode
        }

        recordImageSize(image.size, for: url)
        downsampledCache.setObject(
            image,
            forKey: key as NSString,
            cost: Int(image.size.width * image.size.height)
        )
        return image
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
