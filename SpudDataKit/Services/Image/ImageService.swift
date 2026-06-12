//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import UIKit

public final class ImageService: ImageServiceType, @unchecked Sendable {
    /// In-memory cache for loaded images.
    ///
    /// Each cache entry has associated cost that is the size of the image (width \* height)
    let memoryCache: NSCache<NSURL, UIImage>

    /// Separate cache for decoded animated (GIF) images. Kept apart from
    /// `memoryCache` so a static fetch of the same URL never returns the
    /// multi-frame image (which a `UIImageView` would auto-animate inline).
    let animatedCache: NSCache<NSURL, UIImage>

    let session = URLSession.shared

    let alertService: AlertServiceType

    // MARK: Functions

    public init(alertService: AlertServiceType) {
        self.alertService = alertService

        memoryCache = NSCache()
        // There is no science to this limit, only guesswork.
        memoryCache.countLimit = 100
        // Approx 1GB of memory assuming 1 byte per pixel.
        memoryCache.totalCostLimit = 1024 * 1024 * 1024

        animatedCache = NSCache()
        // Animated images hold every frame, so cap the count tightly.
        animatedCache.countLimit = 16
        animatedCache.totalCostLimit = 1024 * 1024 * 1024
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

                do {
                    let image = try await loadImage(from: url)
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

    /// Download the bytes at `url`, mapping transport and HTTP failures to
    /// `ImageLoadingError`.
    private func data(from url: URL) async throws -> Data {
        // TODO: check if the image is present in URLSession cache.

        let (data, urlResponse): (Data, URLResponse)
        do {
            (data, urlResponse) = try await session.data(from: url)
        } catch {
            throw ImageLoadingError.network(error)
        }

        guard let httpUrlResponse = urlResponse as? HTTPURLResponse else {
            throw ImageLoadingError.cannotDecode
        }

        let statusCode = httpUrlResponse.statusCode
        guard statusCode == 200 else {
            throw ImageLoadingError.serverError(statusCode: statusCode)
        }

        return data
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
            animatedCache.setObject(
                animated,
                forKey: url as NSURL,
                cost: Int(animated.size.width * animated.size.height) * frameCount
            )
            return animated
        }

        // Single frame (or an undecodable animation): treat it as a still image.
        guard let image = UIImage(data: data) else {
            throw ImageLoadingError.cannotDecode
        }
        let decodedImage = await image.byPreparingForDisplay() ?? image
        memoryCache.setObject(
            decodedImage,
            forKey: url as NSURL,
            cost: Int(decodedImage.size.width * decodedImage.size.height)
        )
        return decodedImage
    }
}
