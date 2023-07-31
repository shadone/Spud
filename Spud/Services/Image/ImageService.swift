//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import Foundation
import UIKit

enum ImageLoadingState {
    /// The image is being fetched.
    case loading(thumbnail: UIImage?)

    /// The image was successfully fetched.
    case ready(UIImage)

    /// The image failed to load, we display a broken image icon.
    case failure
}

enum ImageError: Error {
    /// Failed to decode image data.
    case cannotDecode

    /// Failed to fetch the image, the server returned unexpected HTTP status code.
    case serverError(statusCode: Int)

    /// Network error has occurred.
    case network(Error)

    var localizedDescription: String { String(describing: self) }
}

protocol ImageServiceType: AnyObject {
    func fetch(_ url: URL) -> AnyPublisher<ImageLoadingState, Never>
    func fetch(_ url: URL, thumbnail thumbnailUrl: URL?) -> AnyPublisher<ImageLoadingState, Never>
}

extension ImageServiceType {
    func fetch(_ url: URL) -> AnyPublisher<ImageLoadingState, Never> {
        fetch(url, thumbnail: nil)
    }
}

protocol HasImageService {
    var imageService: ImageServiceType { get }
}

class ImageService: ImageServiceType {
    /// In-memory cache for loaded images.
    ///
    /// Each cache entry has associated cost that is the size of the image (width \* height)
    let memoryCache: NSCache<NSURL, UIImage>

    let session = URLSession.shared

    // MARK: Functions

    init() {
        memoryCache = NSCache()
        // There is no science to this limit, only guesswork.
        memoryCache.countLimit = 100
        // Approx 1GB of memory assuming 1 byte per pixel.
        memoryCache.totalCostLimit = 1024 * 1024 * 1024
    }

    func fetch(
        _ url: URL,
        thumbnail thumbnailUrl: URL?
    ) -> AnyPublisher<ImageLoadingState, Never> {
        assert(Thread.isMainThread, "This code is not thread safe")

        if let cachedImage = memoryCache.object(forKey: url as NSURL) {
            // no need to specify .receive(on:) here (neither RunLoop.main nor DispatchQueue.main).
            // Doing do will trigger the callbacks on the next runloop breaking UITableViewCell
            // configuration.
            return .just(.ready(cachedImage))
                .eraseToAnyPublisher()
        }

        // TODO: check if the image is present in URLSession cache.

        let cachedThumbnailImage = thumbnailUrl.flatMap {
            memoryCache.object(forKey: $0 as NSURL)
        }

        return get(url)
            .map { image -> ImageLoadingState in
                .ready(image)
            }
            .catch { imageError -> AnyPublisher<ImageLoadingState, Never> in
                .just(.failure)
            }
            .prepend(.loading(thumbnail: cachedThumbnailImage))
            .eraseToAnyPublisher()
    }

    private func get(_ url: URL) -> AnyPublisher<UIImage, ImageError> {
        assert(Thread.isMainThread, "This code is not thread safe")

        return session.dataTaskPublisher(for: url)
            .mapError { urlError -> ImageError in
                .network(urlError)
            }
            .flatMap { [weak self] (data, urlResponse) -> AnyPublisher<UIImage, ImageError> in
                guard let httpUrlResponse = urlResponse as? HTTPURLResponse else {
                    fatalError("Huh")
                }

                let statusCode = httpUrlResponse.statusCode
                guard statusCode == 200 else {
                    return .fail(with: .serverError(statusCode: statusCode))
                }

                guard let image = UIImage(data: data) else {
                    return .fail(with: .cannotDecode)
                }

                self?.memoryCache.setObject(
                    image,
                    forKey: url as NSURL,
                    cost: Int(image.size.width * image.size.height)
                )

                return .just(image)
            }
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()
    }
}
