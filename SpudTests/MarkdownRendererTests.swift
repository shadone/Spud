//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Down
import UIKit
import XCTest
@testable import Spud

/// Reference-type counter so a `@Sendable` styler closure can record how many
/// times it ran without capturing a mutable local `var`.
private final class StylerInvocationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        value += 1
    }
}

final class MarkdownRendererTests: XCTestCase {
    private func makeStyler() -> @Sendable () -> DownStyler {
        { DownStyler() }
    }

    func test_render_producesAttributedStringFromMarkdown() {
        let renderer = MarkdownRenderer()
        let result = renderer.attributedString(
            markdown: "**bold** text",
            key: "k1",
            makeStyler: makeStyler()
        )
        XCTAssertTrue(result.string.contains("bold"))
        XCTAssertFalse(result.string.contains("**"), "markdown markers should be consumed")
    }

    func test_emptyMarkdown_rendersEmptyString() {
        let renderer = MarkdownRenderer()
        let result = renderer.attributedString(markdown: "", key: "empty", makeStyler: makeStyler())
        XCTAssertEqual(result.string, "")
    }

    func test_secondCall_returnsCachedInstance_withoutReparsing() {
        let renderer = MarkdownRenderer()
        let counter = StylerInvocationCounter()

        let first = renderer.attributedString(markdown: "hello", key: "same", makeStyler: {
            counter.increment()
            return DownStyler()
        })
        let second = renderer.attributedString(markdown: "hello", key: "same", makeStyler: {
            counter.increment()
            return DownStyler()
        })

        XCTAssertTrue(first === second, "same key should return the identical cached instance")
        XCTAssertEqual(counter.count, 1, "styler should only be built on the cache miss")
    }

    func test_cached_returnsNilBeforeRenderAndValueAfter() {
        let renderer = MarkdownRenderer()
        XCTAssertNil(renderer.cached(key: "k"))
        let rendered = renderer.attributedString(markdown: "x", key: "k", makeStyler: makeStyler())
        let cached = renderer.cached(key: "k")
        XCTAssertNotNil(cached)
        XCTAssertTrue(cached === rendered)
    }

    func test_differentKeys_renderIndependently() {
        let renderer = MarkdownRenderer()
        let a = renderer.attributedString(markdown: "alpha", key: "a", makeStyler: makeStyler())
        let b = renderer.attributedString(markdown: "beta", key: "b", makeStyler: makeStyler())
        XCTAssertFalse(a === b)
        XCTAssertTrue(a.string.contains("alpha"))
        XCTAssertTrue(b.string.contains("beta"))
    }

    func test_postBodyKey_variesWithTextSize_butNotForSameInputs() {
        let k1 = MarkdownRenderer.postBodyKey(markdown: "body", textSizeAdjustment: 0)
        let k2 = MarkdownRenderer.postBodyKey(markdown: "body", textSizeAdjustment: 2)
        let k3 = MarkdownRenderer.postBodyKey(markdown: "body", textSizeAdjustment: 0)
        XCTAssertNotEqual(k1, k2, "different text-size adjustments must not collide")
        XCTAssertEqual(k1, k3, "identical inputs must produce the same key")
    }

    func test_prewarmThenMainRead_isCacheHit() async {
        let renderer = MarkdownRenderer()
        let key = "concurrent"
        // Pre-warm off the test's perspective. The rendered string is
        // intentionally discarded so it never crosses the concurrency boundary —
        // each thread reads its own reference out of the thread-safe cache.
        await Task.detached {
            _ = renderer.attributedString(markdown: "warm me", key: key, makeStyler: { DownStyler() })
        }.value
        // The follow-up read finds the cached value.
        XCTAssertNotNil(renderer.cached(key: key))
    }
}
