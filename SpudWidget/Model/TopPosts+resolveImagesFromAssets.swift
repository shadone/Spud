//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import UIKit

extension TopPosts {
    /// Loads images from local resources.
    /// - Note: only useful for previews during development/debugging.
    var resolveImagesFromAssets: [URL: UIImage] {
        let imageUrls = posts
            .compactMap(\.type.imageUrl)

        var imagesByUrl: [URL: UIImage] = [:]
        for url in imageUrls {
            if let image = url.spudImageFromAsset {
                imagesByUrl[url] = image
            }
        }

        return imagesByUrl
    }
}
