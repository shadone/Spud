//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudUtilKit

struct MarkdownPlainTextTests {
    /// One plain-text-preview rule: `MarkdownPlainText.preview(from: input)` must
    /// equal `expected`. `name` documents the rule and is shown in test output.
    struct Case: CustomTestStringConvertible {
        let name: String
        let input: String
        let expected: String
        var testDescription: String {
            name
        }
    }

    @Test(arguments: [
        // Headings
        Case(name: "atxHeading_stripsLeadingHashes", input: "##### This is an automated archive", expected: "This is an automated archive"),
        Case(name: "atxHeading_stripsTrailingHashes", input: "# Title #", expected: "Title"),
        Case(name: "multiBlock_collapsesToOneLine", input: "# Heading\n\nSome intro text.", expected: "Heading Some intro text."),

        // Emphasis
        Case(name: "emphasisMarkers_removed", input: "This is **bold** and *italic* and ~~gone~~.", expected: "This is bold and italic and gone."),
        Case(name: "boldItalicCombo_removed", input: "***wow***", expected: "wow"),
        Case(name: "inlineCode_backticksRemoved", input: "`let x = 1`", expected: "let x = 1"),
        Case(name: "intrawordDoubleUnderscore_survives", input: "call foo__bar__baz now", expected: "call foo__bar__baz now"),
        Case(name: "standaloneDoubleUnderscoreBold_stripped", input: "this __word__ here", expected: "this word here"),
        Case(name: "escapedAsterisks_survivesAsLiteral", input: "\\*not italic\\*", expected: "*not italic*"),

        // Links / images
        Case(name: "inlineLink_keepsTextDropsUrl", input: "see [the docs](https://example.com) now", expected: "see the docs now"),
        Case(name: "image_keepsAltDropsUrl", input: "![a cat](https://example.com/cat.png)", expected: "a cat"),
        Case(name: "referenceStyleLink_keepsText", input: "see [the docs][1] please", expected: "see the docs please"),
        Case(name: "autolink_keepsBareUrl", input: "<https://example.com>", expected: "https://example.com"),

        // Block markers
        Case(name: "blockquoteMarker_removed", input: "> quoted line", expected: "quoted line"),
        Case(name: "multiLevelBlockquote_markersRemoved", input: "> > deep quote", expected: "deep quote"),
        Case(name: "fencedCode_withInfoString_dropsDelimiterAndTag", input: "```swift\nlet x = 1\n```", expected: "let x = 1"),
        Case(name: "tildeFence_dropsDelimiter", input: "~~~\ncode\n~~~", expected: "code"),
        Case(name: "spoilerBlock_titleAndContentKept", input: "::: spoiler Big reveal\nhidden text\n:::", expected: "Big reveal hidden text"),
        Case(name: "unorderedList_markersRemovedAndItemsJoined", input: "- one\n- two", expected: "one two"),
        Case(name: "orderedList_markersRemoved", input: "1. first\n2. second", expected: "first second"),
        Case(name: "thematicBreak_lineDropped", input: "before\n\n---\n\nafter", expected: "before after"),

        // Whitespace / empties
        Case(name: "whitespace_collapsedAndTrimmed", input: "   lots   of    space   ", expected: "lots of space"),
        Case(name: "emptyInput_returnsEmpty", input: "", expected: ""),
        Case(name: "whitespaceOnlyInput_returnsEmpty", input: "   \n\t  \n ", expected: ""),

        // Plain text untouched
        Case(name: "plainParagraph_returnedUnchanged", input: "Just plain text.", expected: "Just plain text."),
        Case(name: "snakeCase_notMangled", input: "call some_function_name here", expected: "call some_function_name here"),
        Case(name: "bareUrl_leftIntact", input: "visit https://example.com today", expected: "visit https://example.com today"),
    ])
    func preview(_ testCase: Case) {
        #expect(MarkdownPlainText.preview(from: testCase.input) == testCase.expected)
    }
}
