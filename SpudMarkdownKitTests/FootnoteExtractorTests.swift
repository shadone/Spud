//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
@testable import SpudMarkdownKit

struct FootnoteExtractorTests {
    @Test
    func extractsDefinitionsAndLeavesReferences() {
        let source = "Thanks.[^1]\n\n[^1]: Re-download over wired."
        let result = FootnoteExtractor.extract(source)
        #expect(result.source.trimmingCharacters(in: .whitespacesAndNewlines) == "Thanks.[^1]")
        #expect(result.definitions.count == 1)
        #expect(result.definitions.first?.label == "1")
        #expect(result.definitions.first?.text == "Re-download over wired.")
    }

    @Test
    func noFootnotes() {
        let result = FootnoteExtractor.extract("Just text.")
        #expect(result.source == "Just text.")
        #expect(result.definitions.isEmpty)
    }

    @Test
    func doesNotExtractDefinitionInsideFencedCode() {
        let source = "```\n[^1]: not a footnote\n```"
        let result = FootnoteExtractor.extract(source)
        #expect(result.definitions.isEmpty)
        #expect(result.source == source)
    }

    @Test
    func extractsDefinitionAfterClosedFence() {
        let source = "```\ncode\n```\n[^1]: real note"
        let result = FootnoteExtractor.extract(source)
        #expect(result.definitions.map(\.label) == ["1"])
        #expect(result.definitions.first?.text == "real note")
    }
}
