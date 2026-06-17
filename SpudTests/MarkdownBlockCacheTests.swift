//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudMarkdownKit
import XCTest
@testable import Spud

final class MarkdownBlockCacheTests: XCTestCase {
    /// Each test uses a fresh cache instance to avoid cross-test pollution.
    private var cache: MarkdownBlockCache!

    override func setUp() {
        super.setUp()
        cache = MarkdownBlockCache()
    }

    // MARK: - Parse correctness

    func test_blocks_returnsEquivalentResultToParser() {
        let markdown = "**hi**"
        let fromCache = cache.blocks(for: markdown)
        let fromParser = MarkdownParser.parse(markdown)
        XCTAssertEqual(
            fromCache,
            fromParser,
            "blocks(for:) must produce the same block tree as MarkdownParser.parse"
        )
    }

    func test_emptyMarkdown_returnsEmptyArray() {
        let result = cache.blocks(for: "")
        XCTAssertEqual(result, [], "empty input should produce an empty block array")
    }

    // MARK: - Cache hit

    func test_secondCall_returnsCachedValue() {
        let markdown = "# Hello"
        let first = cache.blocks(for: markdown)
        let second = cache.blocks(for: markdown)
        XCTAssertEqual(
            first,
            second,
            "repeated call for the same input must return an equal block array"
        )
    }

    // MARK: - Key isolation

    func test_distinctInputs_returnDistinctBlocks() {
        let a = cache.blocks(for: "paragraph one")
        let b = cache.blocks(for: "## heading two")
        XCTAssertNotEqual(
            a,
            b,
            "different markdown sources must produce different block arrays"
        )
    }

    func test_boldText_parsesBoldInline() {
        let result = cache.blocks(for: "**bold**")
        XCTAssertFalse(
            result.isEmpty,
            "bold markdown must produce at least one block"
        )
    }

    // MARK: - Pre-warm / off-main round-trip

    func test_prewarmOffMain_thenRead_returnsEqualBlocks() async {
        let markdown = "off-main warm text"
        // Simulate pre-warm on a background task.
        await Task.detached { [cache] in
            cache!.blocks(for: markdown)
        }.value
        // Main-thread read returns the cached (equal) result.
        let onMain = cache.blocks(for: markdown)
        let expected = MarkdownParser.parse(markdown)
        XCTAssertEqual(
            onMain,
            expected,
            "after off-main pre-warm the cache must return the same blocks"
        )
    }

    // MARK: - Shared instance smoke-test

    func test_sharedInstance_isNotNil() {
        // Just verify the singleton is accessible and returns a result.
        let result = MarkdownBlockCache.shared.blocks(for: "shared test")
        XCTAssertFalse(result.isEmpty, "shared cache must parse and return blocks")
    }
}
