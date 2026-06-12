//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import XCTest
@testable import SpudUtilKit

final class MarkdownFormattingTests: XCTestCase {
    // MARK: Helpers

    /// Applies `action` to `text` with the selection expressed as integer
    /// character offsets, returning the new text plus the new selection as
    /// integer offsets — easy to assert on.
    private func apply(
        _ action: MarkdownFormatting.Action,
        to text: String,
        from lower: Int,
        to upper: Int
    ) -> (text: String, lower: Int, upper: Int) {
        let start = text.index(text.startIndex, offsetBy: lower)
        let end = text.index(text.startIndex, offsetBy: upper)
        let edit = MarkdownFormatting.apply(action, to: text, selection: start..<end)
        let newLower = edit.text.distance(from: edit.text.startIndex, to: edit.selectedRange.lowerBound)
        let newUpper = edit.text.distance(from: edit.text.startIndex, to: edit.selectedRange.upperBound)
        return (edit.text, newLower, newUpper)
    }

    // MARK: Bold

    func test_bold_wrapsSelection() {
        let result = apply(.bold, to: "hello world", from: 6, to: 11)
        XCTAssertEqual(result.text, "hello **world**")
        // The wrapped word remains selected (between the markers).
        XCTAssertEqual(result.lower, 8)
        XCTAssertEqual(result.upper, 13)
        XCTAssertEqual(slice(result), "world")
    }

    func test_bold_emptySelection_insertsPlaceholderSelected() {
        let result = apply(.bold, to: "", from: 0, to: 0)
        XCTAssertEqual(result.text, "**bold text**")
        XCTAssertEqual(slice(result), "bold text")
    }

    func test_bold_togglesOffWhenSelectionAlreadyWrapped() {
        // Selection covers the full "**world**".
        let result = apply(.bold, to: "hello **world**", from: 6, to: 15)
        XCTAssertEqual(result.text, "hello world")
        XCTAssertEqual(slice(result), "world")
    }

    func test_bold_togglesOffWhenMarkersSurroundSelection() {
        // Selection covers only "world", markers sit just outside.
        let result = apply(.bold, to: "hello **world**", from: 8, to: 13)
        XCTAssertEqual(result.text, "hello world")
        XCTAssertEqual(slice(result), "world")
    }

    // MARK: Italic / strikethrough / code

    func test_italic_wrapsSelection() {
        let result = apply(.italic, to: "abc", from: 0, to: 3)
        XCTAssertEqual(result.text, "*abc*")
        XCTAssertEqual(slice(result), "abc")
    }

    func test_strikethrough_wrapsSelection() {
        let result = apply(.strikethrough, to: "abc", from: 0, to: 3)
        XCTAssertEqual(result.text, "~~abc~~")
        XCTAssertEqual(slice(result), "abc")
    }

    func test_inlineCode_wrapsSelection() {
        let result = apply(.code, to: "let x = 1", from: 0, to: 3)
        XCTAssertEqual(result.text, "`let` x = 1")
        XCTAssertEqual(slice(result), "let")
    }

    // MARK: Link

    func test_link_wrapsSelection_andSelectsUrlPlaceholder() {
        let result = apply(.link, to: "click here", from: 6, to: 10)
        XCTAssertEqual(result.text, "click [here](url)")
        // Caret/selection lands on the "url" placeholder.
        XCTAssertEqual(slice(result), "url")
    }

    func test_link_emptySelection_insertsTemplate_andSelectsTextPlaceholder() {
        let result = apply(.link, to: "", from: 0, to: 0)
        XCTAssertEqual(result.text, "[text](url)")
        XCTAssertEqual(slice(result), "text")
    }

    // MARK: Quote / lists (line prefixes)

    func test_quote_prefixesSingleLine() {
        let result = apply(.quote, to: "hello", from: 0, to: 0)
        XCTAssertEqual(result.text, "> hello")
    }

    func test_quote_togglesOffWhenAlreadyPrefixed() {
        let result = apply(.quote, to: "> hello", from: 0, to: 0)
        XCTAssertEqual(result.text, "hello")
    }

    func test_unorderedList_prefixesEverySelectedLine() {
        let text = "one\ntwo\nthree"
        let result = apply(.unorderedList, to: text, from: 0, to: text.count)
        XCTAssertEqual(result.text, "- one\n- two\n- three")
    }

    func test_unorderedList_togglesOffWhenAllPrefixed() {
        let text = "- one\n- two"
        let result = apply(.unorderedList, to: text, from: 0, to: text.count)
        XCTAssertEqual(result.text, "one\ntwo")
    }

    func test_orderedList_numbersEverySelectedLine() {
        let text = "one\ntwo\nthree"
        let result = apply(.orderedList, to: text, from: 0, to: text.count)
        XCTAssertEqual(result.text, "1. one\n2. two\n3. three")
    }

    func test_orderedList_togglesOffWhenAllNumbered() {
        let text = "1. one\n2. two"
        let result = apply(.orderedList, to: text, from: 0, to: text.count)
        XCTAssertEqual(result.text, "one\ntwo")
    }

    func test_linePrefix_appliesToPartialMultilineSelection() {
        // Selection starts mid-first-line and ends mid-second-line; both whole
        // lines should be prefixed.
        let text = "alpha\nbeta\ngamma"
        let result = apply(.quote, to: text, from: 2, to: 8)
        XCTAssertEqual(result.text, "> alpha\n> beta\ngamma")
    }

    // MARK: Code block

    func test_codeBlock_wrapsSelectionInFence() {
        let result = apply(.codeBlock, to: "", from: 0, to: 0)
        XCTAssertEqual(result.text, "```\ncode\n```\n")
        XCTAssertEqual(slice(result), "code")
    }

    func test_codeBlock_insertsLeadingNewlineWhenMidText() {
        let text = "intro"
        let result = apply(.codeBlock, to: text, from: 5, to: 5)
        XCTAssertEqual(result.text, "intro\n```\ncode\n```\n")
    }

    // MARK: Spoiler

    func test_spoiler_wrapsInLemmySpoilerBlock_andSelectsTitle() {
        let result = apply(.spoiler, to: "", from: 0, to: 0)
        XCTAssertEqual(result.text, "::: spoiler title\nspoiler content\n:::\n")
        XCTAssertEqual(slice(result), "title")
    }

    func test_spoiler_wrapsExistingSelectionAsBody() {
        let text = "secret"
        let result = apply(.spoiler, to: text, from: 0, to: 6)
        XCTAssertEqual(result.text, "::: spoiler title\nsecret\n:::\n")
        XCTAssertEqual(slice(result), "title")
    }

    // MARK: Slice helper

    private func slice(_ result: (text: String, lower: Int, upper: Int)) -> String {
        let start = result.text.index(result.text.startIndex, offsetBy: result.lower)
        let end = result.text.index(result.text.startIndex, offsetBy: result.upper)
        return String(result.text[start..<end])
    }
}
