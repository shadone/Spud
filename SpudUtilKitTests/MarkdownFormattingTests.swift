//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudUtilKit

struct MarkdownFormattingTests {
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

    @Test
    func bold_wrapsSelection() {
        let result = apply(.bold, to: "hello world", from: 6, to: 11)
        #expect(result.text == "hello **world**")
        // The wrapped word remains selected (between the markers).
        #expect(result.lower == 8)
        #expect(result.upper == 13)
        #expect(slice(result) == "world")
    }

    @Test
    func bold_emptySelection_insertsPlaceholderSelected() {
        let result = apply(.bold, to: "", from: 0, to: 0)
        #expect(result.text == "**bold text**")
        #expect(slice(result) == "bold text")
    }

    @Test
    func bold_togglesOffWhenSelectionAlreadyWrapped() {
        // Selection covers the full "**world**".
        let result = apply(.bold, to: "hello **world**", from: 6, to: 15)
        #expect(result.text == "hello world")
        #expect(slice(result) == "world")
    }

    @Test
    func bold_togglesOffWhenMarkersSurroundSelection() {
        // Selection covers only "world", markers sit just outside.
        let result = apply(.bold, to: "hello **world**", from: 8, to: 13)
        #expect(result.text == "hello world")
        #expect(slice(result) == "world")
    }

    // MARK: Italic / strikethrough / code

    @Test
    func italic_wrapsSelection() {
        let result = apply(.italic, to: "abc", from: 0, to: 3)
        #expect(result.text == "*abc*")
        #expect(slice(result) == "abc")
    }

    @Test
    func strikethrough_wrapsSelection() {
        let result = apply(.strikethrough, to: "abc", from: 0, to: 3)
        #expect(result.text == "~~abc~~")
        #expect(slice(result) == "abc")
    }

    @Test
    func inlineCode_wrapsSelection() {
        let result = apply(.code, to: "let x = 1", from: 0, to: 3)
        #expect(result.text == "`let` x = 1")
        #expect(slice(result) == "let")
    }

    // MARK: Link

    @Test
    func link_wrapsSelection_andSelectsUrlPlaceholder() {
        let result = apply(.link, to: "click here", from: 6, to: 10)
        #expect(result.text == "click [here](url)")
        // Caret/selection lands on the "url" placeholder.
        #expect(slice(result) == "url")
    }

    @Test
    func link_emptySelection_insertsTemplate_andSelectsTextPlaceholder() {
        let result = apply(.link, to: "", from: 0, to: 0)
        #expect(result.text == "[text](url)")
        #expect(slice(result) == "text")
    }

    // MARK: Quote / lists (line prefixes)

    @Test
    func quote_prefixesSingleLine() {
        let result = apply(.quote, to: "hello", from: 0, to: 0)
        #expect(result.text == "> hello")
    }

    @Test
    func quote_togglesOffWhenAlreadyPrefixed() {
        let result = apply(.quote, to: "> hello", from: 0, to: 0)
        #expect(result.text == "hello")
    }

    @Test
    func unorderedList_prefixesEverySelectedLine() {
        let text = "one\ntwo\nthree"
        let result = apply(.unorderedList, to: text, from: 0, to: text.count)
        #expect(result.text == "- one\n- two\n- three")
    }

    @Test
    func unorderedList_togglesOffWhenAllPrefixed() {
        let text = "- one\n- two"
        let result = apply(.unorderedList, to: text, from: 0, to: text.count)
        #expect(result.text == "one\ntwo")
    }

    @Test
    func orderedList_numbersEverySelectedLine() {
        let text = "one\ntwo\nthree"
        let result = apply(.orderedList, to: text, from: 0, to: text.count)
        #expect(result.text == "1. one\n2. two\n3. three")
    }

    @Test
    func orderedList_togglesOffWhenAllNumbered() {
        let text = "1. one\n2. two"
        let result = apply(.orderedList, to: text, from: 0, to: text.count)
        #expect(result.text == "one\ntwo")
    }

    @Test
    func linePrefix_appliesToPartialMultilineSelection() {
        // Selection starts mid-first-line and ends mid-second-line; both whole
        // lines should be prefixed.
        let text = "alpha\nbeta\ngamma"
        let result = apply(.quote, to: text, from: 2, to: 8)
        #expect(result.text == "> alpha\n> beta\ngamma")
    }

    // MARK: Code block

    @Test
    func codeBlock_wrapsSelectionInFence() {
        let result = apply(.codeBlock, to: "", from: 0, to: 0)
        #expect(result.text == "```\ncode\n```\n")
        #expect(slice(result) == "code")
    }

    @Test
    func codeBlock_insertsLeadingNewlineWhenMidText() {
        let text = "intro"
        let result = apply(.codeBlock, to: text, from: 5, to: 5)
        #expect(result.text == "intro\n```\ncode\n```\n")
    }

    // MARK: Spoiler

    @Test
    func spoiler_wrapsInLemmySpoilerBlock_andSelectsTitle() {
        let result = apply(.spoiler, to: "", from: 0, to: 0)
        #expect(result.text == "::: spoiler title\nspoiler content\n:::\n")
        #expect(slice(result) == "title")
    }

    @Test
    func spoiler_wrapsExistingSelectionAsBody() {
        let text = "secret"
        let result = apply(.spoiler, to: text, from: 0, to: 6)
        #expect(result.text == "::: spoiler title\nsecret\n:::\n")
        #expect(slice(result) == "title")
    }

    // MARK: Slice helper

    private func slice(_ result: (text: String, lower: Int, upper: Int)) -> String {
        let start = result.text.index(result.text.startIndex, offsetBy: result.lower)
        let end = result.text.index(result.text.startIndex, offsetBy: result.upper)
        return String(result.text[start..<end])
    }
}
