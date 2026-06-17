//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import SpudMarkdownKit

final class SpoilerPreprocessorTests: XCTestCase {
    func test_extractsSpoilerWithTitleAndInner() throws {
        let source = "Intro\n\n::: spoiler Benchmarks\nLocked 60 fps.\n:::\n\nOutro"
        let result = SpoilerPreprocessor.preprocess(source)

        XCTAssertEqual(result.spoilers.count, 1)
        let spoiler = result.spoilers.values.first
        XCTAssertEqual(spoiler?.title, "Benchmarks")
        XCTAssertEqual(spoiler?.inner.trimmingCharacters(in: .whitespacesAndNewlines), "Locked 60 fps.")

        XCTAssertFalse(result.source.contains("::: spoiler"))
        XCTAssertTrue(result.source.contains("Intro"))
        XCTAssertTrue(result.source.contains("Outro"))
        let id = try XCTUnwrap(result.spoilers.keys.first)
        XCTAssertTrue(result.source.contains(SpoilerPreprocessor.sentinel(for: id)))
    }

    func test_emptyTitle() {
        let result = SpoilerPreprocessor.preprocess("::: spoiler\nhidden\n:::")
        XCTAssertEqual(result.spoilers.values.first?.title, "")
    }

    func test_noSpoiler() {
        let result = SpoilerPreprocessor.preprocess("plain text")
        XCTAssertEqual(result.source, "plain text")
        XCTAssertTrue(result.spoilers.isEmpty)
    }

    func test_doesNotLiftSpoilerInsideFencedCode() {
        let source = "```\n::: spoiler secret\nhidden\n:::\n```"
        let result = SpoilerPreprocessor.preprocess(source)
        XCTAssertTrue(result.spoilers.isEmpty)
        XCTAssertEqual(result.source, source)
    }

    func test_liftsSpoilerAfterClosedFence() {
        let source = "```\ncode\n```\n\n::: spoiler Real\ninner\n:::"
        let result = SpoilerPreprocessor.preprocess(source)
        XCTAssertEqual(result.spoilers.count, 1)
        XCTAssertEqual(result.spoilers.values.first?.title, "Real")
        XCTAssertTrue(result.source.contains("```\ncode\n```"))
    }
}
