//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
@testable import SpudMarkdownKit

struct SpoilerPreprocessorTests {
    @Test
    func extractsSpoilerWithTitleAndInner() throws {
        let source = "Intro\n\n::: spoiler Benchmarks\nLocked 60 fps.\n:::\n\nOutro"
        let result = SpoilerPreprocessor.preprocess(source)

        #expect(result.spoilers.count == 1)
        let spoiler = result.spoilers.values.first
        #expect(spoiler?.title == "Benchmarks")
        #expect(spoiler?.inner.trimmingCharacters(in: .whitespacesAndNewlines) == "Locked 60 fps.")

        #expect(!result.source.contains("::: spoiler"))
        #expect(result.source.contains("Intro"))
        #expect(result.source.contains("Outro"))
        let id = try #require(result.spoilers.keys.first)
        #expect(result.source.contains(SpoilerPreprocessor.sentinel(for: id)))
    }

    @Test
    func emptyTitle() {
        let result = SpoilerPreprocessor.preprocess("::: spoiler\nhidden\n:::")
        #expect(result.spoilers.values.first?.title == "")
    }

    @Test
    func noSpoiler() {
        let result = SpoilerPreprocessor.preprocess("plain text")
        #expect(result.source == "plain text")
        #expect(result.spoilers.isEmpty)
    }

    @Test
    func doesNotLiftSpoilerInsideFencedCode() {
        let source = "```\n::: spoiler secret\nhidden\n:::\n```"
        let result = SpoilerPreprocessor.preprocess(source)
        #expect(result.spoilers.isEmpty)
        #expect(result.source == source)
    }

    @Test
    func liftsSpoilerAfterClosedFence() {
        let source = "```\ncode\n```\n\n::: spoiler Real\ninner\n:::"
        let result = SpoilerPreprocessor.preprocess(source)
        #expect(result.spoilers.count == 1)
        #expect(result.spoilers.values.first?.title == "Real")
        #expect(result.source.contains("```\ncode\n```"))
    }
}
