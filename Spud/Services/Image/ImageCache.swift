//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import UIKit

class ImageCache {
    struct CacheItem {
        let image: UIImage
        let url: URL
        let accessTimestamp: Date
    }

    private var cache: [URL: CacheItem] = [:]
    private let maxNumberOfItems = 100

    func add(_ image: UIImage, for url: URL) {
        cache[url] = CacheItem(image: image, url: url, accessTimestamp: Date())
        evictIfNeeded()
    }

    func get(for url: URL) -> UIImage? {
        cache[url]?.image
    }

    private func evictIfNeeded() {
        if cache.count > maxNumberOfItems {
            // sort cached items by access time from most recent to oldest.
            var sortedItems = cache.values
                .sorted(by: { $0.accessTimestamp > $1.accessTimestamp })

            while sortedItems.count > maxNumberOfItems {
                let item = sortedItems.popLast()
                assert(item != nil)
                cache.removeValue(forKey: item!.url)
            }
        }
    }
}
