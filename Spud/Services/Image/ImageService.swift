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
    case network(Error)
    case invalid

    var localizedDescription: String { String(describing: self) }
}

protocol ImageServiceType: AnyObject {
    // TODO: deprecate get() in favour of fetch(); make get() private
    func get(_ url: URL) -> AnyPublisher<UIImage, ImageError>

    func fetch(_ url: URL, thumbnail thumbnailUrl: URL?) -> AnyPublisher<ImageLoadingState, Never>
}

protocol HasImageService {
    var imageService: ImageServiceType { get }
}

class ImageService: ImageServiceType {
    let memoryCache = ImageCache()

    let session = URLSession.shared

    func fetch(
        _ url: URL,
        thumbnail thumbnailUrl: URL?
    ) -> AnyPublisher<ImageLoadingState, Never> {
        assert(Thread.isMainThread, "This code is not thread safe")

        if let cachedImage = memoryCache.get(for: url) {
            // no need to specify .receive(on:) here (neither RunLoop.main nor DispatchQueue.main).
            // Doing do will trigger the callbacks on the next runloop breaking UITableViewCell
            // configuration.
            return .just(.ready(cachedImage))
                .eraseToAnyPublisher()
        }

        // TODO: check if the image is present in URLSession cache.

        let cachedThumbnailImage = thumbnailUrl.flatMap { memoryCache.get(for: $0) }

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

    func get(_ url: URL) -> AnyPublisher<UIImage, ImageError> {
        assert(Thread.isMainThread, "This code is not thread safe")

        if let cachedImage = memoryCache.get(for: url) {
            return .just(cachedImage)
                .receive(on: RunLoop.main)
                .eraseToAnyPublisher()
        }

        return session.dataTaskPublisher(for: url)
            .mapError { urlError -> ImageError in
                .network(urlError)
            }
            .flatMap { [weak self] pair -> AnyPublisher<UIImage, ImageError> in
                guard let response = pair.response as? HTTPURLResponse else {
                    assertionFailure()
                    return .fail(with: .invalid)
                }

                guard response.statusCode == 200 else {
                    return .fail(with: .invalid)
                }

                guard let image = UIImage(data: pair.data) else {
                    return .fail(with: .invalid)
                }

                self?.memoryCache.add(image, for: url)

                return .just(image)
            }
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()
    }
}
