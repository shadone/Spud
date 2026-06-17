//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import SpudMarkdownKit

final class FootnoteExtractorTests: XCTestCase {
    func test_extractsDefinitionsAndLeavesReferences() {
        let source = "Thanks.[^1]\n\n[^1]: Re-download over wired."
        let result = FootnoteExtractor.extract(source)
        XCTAssertEqual(result.source.trimmingCharacters(in: .whitespacesAndNewlines), "Thanks.[^1]")
        XCTAssertEqual(result.definitions.count, 1)
        XCTAssertEqual(result.definitions.first?.label, "1")
        XCTAssertEqual(result.definitions.first?.text, "Re-download over wired.")
    }

    func test_noFootnotes() {
        let result = FootnoteExtractor.extract("Just text.")
        XCTAssertEqual(result.source, "Just text.")
        XCTAssertTrue(result.definitions.isEmpty)
    }

    func test_doesNotExtractDefinitionInsideFencedCode() {
        let source = "```\n[^1]: not a footnote\n```"
        let result = FootnoteExtractor.extract(source)
        XCTAssertTrue(result.definitions.isEmpty)
        XCTAssertEqual(result.source, source)
    }

    func test_extractsDefinitionAfterClosedFence() {
        let source = "```\ncode\n```\n[^1]: real note"
        let result = FootnoteExtractor.extract(source)
        XCTAssertEqual(result.definitions.map(\.label), ["1"])
        XCTAssertEqual(result.definitions.first?.text, "real note")
    }
}
