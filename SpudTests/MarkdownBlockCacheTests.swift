//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudMarkdownKit
import Testing
@testable import Spud

struct MarkdownBlockCacheTests {
    /// Each test uses a fresh cache instance to avoid cross-test pollution.
    let cache = MarkdownBlockCache()

    // MARK: - Parse correctness

    @Test
    func blocks_returnsEquivalentResultToParser() {
        let markdown = "**hi**"
        let fromCache = cache.blocks(for: markdown)
        let fromParser = MarkdownParser.parse(markdown)
        #expect(
            fromCache == fromParser,
            "blocks(for:) must produce the same block tree as MarkdownParser.parse"
        )
    }

    @Test
    func emptyMarkdown_returnsEmptyArray() {
        let result = cache.blocks(for: "")
        #expect(result == [], "empty input should produce an empty block array")
    }

    // MARK: - Cache hit

    @Test
    func secondCall_returnsCachedValue() {
        let markdown = "# Hello"
        let first = cache.blocks(for: markdown)
        let second = cache.blocks(for: markdown)
        #expect(
            first == second,
            "repeated call for the same input must return an equal block array"
        )
    }

    // MARK: - Key isolation

    @Test
    func distinctInputs_returnDistinctBlocks() {
        let a = cache.blocks(for: "paragraph one")
        let b = cache.blocks(for: "## heading two")
        #expect(
            a != b,
            "different markdown sources must produce different block arrays"
        )
    }

    @Test
    func boldText_parsesBoldInline() {
        let result = cache.blocks(for: "**bold**")
        #expect(
            !result.isEmpty,
            "bold markdown must produce at least one block"
        )
    }

    // MARK: - Pre-warm / off-main round-trip

    @Test
    func prewarmOffMain_thenRead_returnsEqualBlocks() async {
        let markdown = "off-main warm text"
        // Simulate pre-warm on a background task.
        await Task.detached { [cache] in
            cache.blocks(for: markdown)
        }.value
        // Main-thread read returns the cached (equal) result.
        let onMain = cache.blocks(for: markdown)
        let expected = MarkdownParser.parse(markdown)
        #expect(
            onMain == expected,
            "after off-main pre-warm the cache must return the same blocks"
        )
    }

    // MARK: - Shared instance smoke-test

    @Test
    func sharedInstance_isNotNil() {
        // Just verify the singleton is accessible and returns a result.
        let result = MarkdownBlockCache.shared.blocks(for: "shared test")
        #expect(!result.isEmpty, "shared cache must parse and return blocks")
    }
}
