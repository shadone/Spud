//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import Foundation

public protocol ImageServiceType: AnyObject {
    func fetch(_ url: URL) -> AnyPublisher<ImageLoadingState, Never>
    func fetch(_ url: URL, thumbnail thumbnailUrl: URL?) -> AnyPublisher<ImageLoadingState, Never>
}

public extension ImageServiceType {
    func fetch(_ url: URL) -> AnyPublisher<ImageLoadingState, Never> {
        fetch(url, thumbnail: nil)
    }
}

public protocol HasImageService {
    var imageService: ImageServiceType { get }
}
