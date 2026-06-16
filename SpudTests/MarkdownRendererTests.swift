//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Down
import SpudUtilKit
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

    // MARK: - Autolinking bare URLs

    /// Helper: the first `.link` value found in the rendered string, normalised
    /// to a URL (the styler stores explicit links as `String`, the autolink pass
    /// stores them as `URL`).
    private func firstLink(in attributed: NSAttributedString) -> URL? {
        var found: URL?
        attributed.enumerateAttribute(
            .link,
            in: NSRange(location: 0, length: attributed.length)
        ) { value, _, stop in
            if let url = value as? URL {
                found = url
                stop.pointee = true
            } else if let string = value as? String, let url = URL(string: string) {
                found = url
                stop.pointee = true
            }
        }
        return found
    }

    private func hasAnyLink(in attributed: NSAttributedString) -> Bool {
        var has = false
        attributed.enumerateAttribute(
            .link,
            in: NSRange(location: 0, length: attributed.length)
        ) { value, _, stop in
            if value != nil {
                has = true
                stop.pointee = true
            }
        }
        return has
    }

    func test_bareURL_inBodyText_isLinkified() {
        let renderer = MarkdownRenderer()
        let result = renderer.attributedString(
            markdown: "Full video here: https://youtu.be/0ORqQPk7kjs",
            key: "bareURL",
            makeStyler: makeStyler()
        )
        XCTAssertEqual(
            firstLink(in: result)?.absoluteString,
            "https://youtu.be/0ORqQPk7kjs",
            "a bare URL in post text should become a tappable link"
        )
    }

    func test_explicitMarkdownLink_isStillLinkified() {
        let renderer = MarkdownRenderer()
        let result = renderer.attributedString(
            markdown: "[watch](https://youtu.be/0ORqQPk7kjs)",
            key: "explicitLink",
            makeStyler: makeStyler()
        )
        XCTAssertEqual(result.string, "watch", "the link label, not the URL, is shown")
        XCTAssertEqual(firstLink(in: result)?.absoluteString, "https://youtu.be/0ORqQPk7kjs")
    }

    func test_urlInsideInlineCode_isNotLinkified() {
        let renderer = MarkdownRenderer()
        let result = renderer.attributedString(
            markdown: "run `curl https://example.com` to fetch",
            key: "codeURL",
            makeStyler: makeStyler()
        )
        XCTAssertFalse(
            hasAnyLink(in: result),
            "URLs inside code spans should not be autolinked"
        )
    }

    func test_plainText_hasNoLink() {
        let renderer = MarkdownRenderer()
        let result = renderer.attributedString(
            markdown: "just some words, no links here",
            key: "noURL",
            makeStyler: makeStyler()
        )
        XCTAssertFalse(hasAnyLink(in: result))
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

    // MARK: - Lemmy mention shorthands

    func test_communityMention_isLinkifiedToInternalLink() {
        let renderer = MarkdownRenderer()
        let result = renderer.attributedString(
            markdown: "join !technology@beehaw.org today",
            key: "communityMention",
            makeStyler: makeStyler()
        )
        guard
            let link = firstLink(in: result),
            case let .community(name, instance)? = link.spud
        else {
            return XCTFail("community mention should become an internal community link")
        }
        XCTAssertEqual(name, "technology")
        XCTAssertEqual(instance.host, "beehaw.org")
    }

    func test_userMention_isLinkifiedToInternalLink() {
        let renderer = MarkdownRenderer()
        let result = renderer.attributedString(
            markdown: "ping @alice@lemmy.world ok",
            key: "userMention",
            makeStyler: makeStyler()
        )
        guard
            let link = firstLink(in: result),
            case let .objectAtURL(url)? = link.spud
        else {
            return XCTFail("user mention should become an internal resolve link")
        }
        XCTAssertEqual(url.absoluteString, "https://lemmy.world/u/alice")
    }

    func test_mentionInsideInlineCode_isNotLinkified() {
        let renderer = MarkdownRenderer()
        let result = renderer.attributedString(
            markdown: "type `!technology@beehaw.org` to subscribe",
            key: "codeMention",
            makeStyler: makeStyler()
        )
        XCTAssertFalse(hasAnyLink(in: result), "mentions inside code spans must not be linkified")
    }

    /// Both passes in one body: the mention becomes an internal link while a real
    /// bare URL stays a plain external link (URL classification happens at tap time).
    func test_mentionAndBareURL_coexistWithCorrectKinds() {
        let renderer = MarkdownRenderer()
        let result = renderer.attributedString(
            markdown: "see !tech@beehaw.org or https://lemmy.world/post/5",
            key: "mixedMentionAndURL",
            makeStyler: makeStyler()
        )
        var links: [URL] = []
        result.enumerateAttribute(.link, in: NSRange(location: 0, length: result.length)) { value, _, _ in
            if let url = value as? URL {
                links.append(url)
            } else if let string = value as? String, let url = URL(string: string) {
                links.append(url)
            }
        }
        let communityLinks = links.filter { if case .community? = $0.spud { return true } else { return false } }
        let externalLinks = links.filter { $0.spud == nil }
        XCTAssertEqual(communityLinks.count, 1, "the mention should be a single internal community link")
        XCTAssertEqual(
            externalLinks.first?.absoluteString,
            "https://lemmy.world/post/5",
            "the bare URL should remain a plain external link in the rendered text"
        )
    }
}
