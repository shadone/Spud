//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
@testable import SpudMarkdownKit

struct SubSupPreprocessorTests {
    @Test
    func protectsSuperscript() {
        #expect(SubSupPreprocessor.protectText("x^2^") == "x\u{E010}sup:2\u{E011}")
    }

    @Test
    func protectsSubscript() {
        #expect(SubSupPreprocessor.protectText("H~2~O") == "H\u{E010}sub:2\u{E011}O")
    }

    @Test
    func leavesDoubleTildeStrikethroughAlone() {
        #expect(SubSupPreprocessor.protectText("~~gone~~") == "~~gone~~")
    }

    @Test
    func doesNotProtectInsideFencedCode() {
        let source = "```\nx^2^ and H~2~O\n```"
        #expect(SubSupPreprocessor.protectText(source) == source)
    }

    @Test
    func protectsAfterClosedFence() {
        let source = "```\ncode\n```\nx^2^"
        #expect(SubSupPreprocessor.protectText(source) == "```\ncode\n```\nx\u{E010}sup:2\u{E011}")
    }
}
