//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import Foundation
import UIKit

public final class ImageService: ImageServiceType, @unchecked Sendable {
    /// In-memory cache for loaded images.
    ///
    /// Each cache entry has associated cost that is the size of the image (width \* height)
    let memoryCache: NSCache<NSURL, UIImage>

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

    public func fetchPublisher(
        _ url: URL,
        thumbnail thumbnailUrl: URL?
    ) -> AnyPublisher<ImageLoadingState, Never> {
        let subject = PassthroughSubject<ImageLoadingState, Never>()
        let stream = fetch(url, thumbnail: thumbnailUrl)
        let task = Task {
            for await state in stream {
                subject.send(state)
            }
            subject.send(completion: .finished)
        }
        return subject
            .handleEvents(receiveCancel: { task.cancel() })
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    private func loadImage(from url: URL) async throws -> UIImage {
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

        guard let image = UIImage(data: data) else {
            throw ImageLoadingError.cannotDecode
        }

        memoryCache.setObject(
            image,
            forKey: url as NSURL,
            cost: Int(image.size.width * image.size.height)
        )

        return image
    }
}
