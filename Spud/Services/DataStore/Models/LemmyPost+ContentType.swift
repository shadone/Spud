//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import Foundation

extension LemmyPost {
    /// Describes the thumbnail of the post.
    enum ThumbnailType {
        /// Thumbnail is an image.
        case image(URL)

        /// There is not image available, the thumbnail is a text-post indicator.
        case text
    }

    var thumbnailType: AnyPublisher<ThumbnailType, Never> {
        publisher(for: \.thumbnailUrl)
            .map { thumbnailUrl in
                if let thumbnailUrl = thumbnailUrl {
                    return .image(thumbnailUrl)
                }
                return .text
            }
            .eraseToAnyPublisher()
    }
}
