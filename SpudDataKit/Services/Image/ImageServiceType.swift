//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import Foundation

public protocol ImageServiceType: AnyObject {
    /// Asynchronously fetch the image at `url`, optionally yielding a thumbnail
    /// while the full image loads.
    ///
    /// The stream emits `.loading(thumbnail:)` first, then either `.ready(image)`
    /// on success or `.failure` on error, and then completes.
    func fetch(_ url: URL, thumbnail thumbnailUrl: URL?) -> AsyncStream<ImageLoadingState>

    /// Combine wrapper around ``fetch(_:thumbnail:)``. Will be removed once
    /// ViewModels migrate off Combine.
    func fetchPublisher(
        _ url: URL,
        thumbnail thumbnailUrl: URL?
    ) -> AnyPublisher<ImageLoadingState, Never>
}

public extension ImageServiceType {
    func fetch(_ url: URL) -> AsyncStream<ImageLoadingState> {
        fetch(url, thumbnail: nil)
    }

    func fetchPublisher(_ url: URL) -> AnyPublisher<ImageLoadingState, Never> {
        fetchPublisher(url, thumbnail: nil)
    }
}

@MainActor
public protocol HasImageService {
    var imageService: ImageServiceType { get }
}
