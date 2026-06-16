//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Down
import Foundation
import UIKit

/// Thread-safe markdown -> `NSAttributedString` cache.
///
/// Parsing markdown (cmark) and building the styled attributed string is the
/// most expensive work done while configuring a comment cell. It used to run
/// synchronously on the main thread every time a cell was dequeued, so a long
/// thread stuttered on scroll. This caches the rendered attributed string keyed
/// by the markdown source plus a styling key.
///
/// The renderer is safe to call from any thread, which lets the comment list
/// pre-warm the cache off the main thread before cells are configured: a
/// background pass renders every visible body into the cache, then the
/// main-thread cell configuration hits the cache instead of parsing. The
/// attributed strings never cross a concurrency boundary as passed values —
/// each thread reads its own reference out of the thread-safe `NSCache`.
///
/// Dynamic system colors (`UIColor.label`, `UIColor.link`, …) stored as
/// attributes still resolve light/dark at draw time, so the cache key only needs
/// to vary with parameters that change the *baked* output, i.e. font sizing.
final class MarkdownRenderer: @unchecked Sendable {
    static let shared = MarkdownRenderer()

    /// `NSCache` is documented thread-safe for concurrent get/set, so no extra
    /// lock is needed around it.
    private let cache: NSCache<NSString, NSAttributedString>

    init(countLimit: Int = 600) {
        cache = NSCache()
        cache.countLimit = countLimit
    }

    /// The cached render for `key`, or `nil` if it has not been rendered yet.
    func cached(key: String) -> NSAttributedString? {
        cache.object(forKey: key as NSString)
    }

    /// Renders `markdown` to a styled attributed string, caching the result
    /// under `key`. `makeStyler` is invoked only on a cache miss.
    ///
    /// Safe to call from any thread. Call it off the main thread to pre-warm the
    /// cache before the value is needed on the main thread; the on-main call then
    /// returns the cached value without parsing.
    @discardableResult
    func attributedString(
        markdown: String,
        key: String,
        makeStyler: @Sendable () -> DownStyler
    ) -> NSAttributedString {
        let nsKey = key as NSString
        if let cached = cache.object(forKey: nsKey) {
            return cached
        }

        let rendered: NSAttributedString
        if markdown.isEmpty {
            rendered = NSAttributedString()
        } else {
            rendered = Down(markdownString: markdown)
                .toAttributedString(styler: makeStyler())
                .addingAutolinks()
        }

        cache.setObject(rendered, forKey: nsKey)
        return rendered
    }

    /// Cache key for a post-body preview rendered into a plain `UILabel` (the
    /// feed-card path in `PostPreviewViewController`) with the shared
    /// `PostDetailAppearance` body styler. The post-detail and comment bodies
    /// render through `SpudMarkdownKit`/`MarkdownBodyView` instead. Bump the
    /// version when the styler changes.
    static func postBodyKey(markdown: String, textSizeAdjustment: CGFloat) -> String {
        "postBody.v1.\(textSizeAdjustment)\u{1}\(markdown)"
    }
}
