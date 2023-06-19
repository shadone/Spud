//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import Foundation
import UIKit

enum ImageError: Error {
    case network(Error)
    case invalid

    var localizedDescription: String { String(describing: self) }
}

protocol ImageServiceType: AnyObject {
    func get(_ url: URL) -> AnyPublisher<UIImage, ImageError>
}

protocol HasImageService {
    var imageService: ImageServiceType { get }
}

class ImageService: ImageServiceType {
    let memoryCache = ImageCache()

    func get(_ url: URL) -> AnyPublisher<UIImage, ImageError> {
        assert(Thread.isMainThread, "This code is not thread safe")

        if let cachedImage = memoryCache.get(for: url) {
            return .just(cachedImage)
                .receive(on: DispatchQueue.main)
                .eraseToAnyPublisher()
        }

        return URLSession.shared.dataTaskPublisher(for: url)
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
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
}
