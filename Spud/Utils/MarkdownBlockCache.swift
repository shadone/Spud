//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudMarkdownKit

/// Thread-safe markdown -> `[MarkdownBlock]` parse cache.
///
/// `MarkdownParser.parse` is pure and synchronous, so the block tree does not
/// depend on any rendering context — the cache key is just the markdown source.
/// Parsed blocks are stored so they can be shared across any rendering pass
/// (e.g. the new `MarkdownBlockView` path and the legacy `MarkdownRenderer`
/// path during the transitional period).
///
/// The pre-warm pattern mirrors `MarkdownRenderer`: call `blocks(for:)` off the
/// main thread before cells are configured, so cell dequeue is a warm cache hit
/// rather than a synchronous parse on the scroll path.
///
/// `NSCache` is thread-safe for concurrent get/set; wrapping `[MarkdownBlock]`
/// in a reference-type box lets `NSCache<NSString, BlockBox>` store the value
/// type array.
final class MarkdownBlockCache: @unchecked Sendable {
    static let shared = MarkdownBlockCache()

    // MARK: - Private

    private final class BlockBox {
        let blocks: [MarkdownBlock]
        init(_ blocks: [MarkdownBlock]) {
            self.blocks = blocks
        }
    }

    private let cache: NSCache<NSString, BlockBox>

    // MARK: - Init

    init(countLimit: Int = 600) {
        cache = NSCache()
        cache.countLimit = countLimit
    }

    // MARK: - Public API

    /// Returns the cached block array for `markdown`, parsing and caching on a
    /// miss. Safe to call from any thread.
    @discardableResult
    func blocks(for markdown: String) -> [MarkdownBlock] {
        let key = ("blocks.v1." + markdown) as NSString
        if let box = cache.object(forKey: key) {
            return box.blocks
        }
        let parsed = MarkdownParser.parse(markdown)
        cache.setObject(BlockBox(parsed), forKey: key)
        return parsed
    }
}
