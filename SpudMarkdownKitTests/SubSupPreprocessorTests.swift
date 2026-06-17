//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import SpudMarkdownKit

final class SubSupPreprocessorTests: XCTestCase {
    func test_protectsSuperscript() {
        XCTAssertEqual(SubSupPreprocessor.protectText("x^2^"), "x\u{E010}sup:2\u{E011}")
    }

    func test_protectsSubscript() {
        XCTAssertEqual(SubSupPreprocessor.protectText("H~2~O"), "H\u{E010}sub:2\u{E011}O")
    }

    func test_leavesDoubleTildeStrikethroughAlone() {
        XCTAssertEqual(SubSupPreprocessor.protectText("~~gone~~"), "~~gone~~")
    }

    func test_doesNotProtectInsideFencedCode() {
        let source = "```\nx^2^ and H~2~O\n```"
        XCTAssertEqual(SubSupPreprocessor.protectText(source), source)
    }

    func test_protectsAfterClosedFence() {
        let source = "```\ncode\n```\nx^2^"
        XCTAssertEqual(SubSupPreprocessor.protectText(source), "```\ncode\n```\nx\u{E010}sup:2\u{E011}")
    }
}
