//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit
import XCTest
@testable import SpudMarkdownKit

@MainActor
final class InlineAttributedStringBuilderTests: XCTestCase {
    private func build(_ inlines: [MarkdownInline]) -> NSAttributedString {
        InlineAttributedStringBuilder.build(inlines, context: MarkdownContext(kind: .post))
    }

    func test_plainText() {
        XCTAssertEqual(build([.text("hello")]).string, "hello")
    }

    func test_strongIsBold() {
        let s = build([.strong([.text("x")])])
        let font = s.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false)
    }

    func test_emphasisIsItalic() {
        let s = build([.emphasis([.text("x")])])
        let font = s.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.traitItalic) ?? false)
    }

    func test_linkCarriesURL() throws {
        let url = try XCTUnwrap(URL(string: "https://lemmy.world/post/1"))
        let s = build([.link(text: [.text("here")], url: url)])
        XCTAssertEqual(s.attribute(.link, at: 0, effectiveRange: nil) as? URL, url)
    }

    func test_highlightHasBackground() {
        let s = build([.highlight([.text("x")])])
        XCTAssertNotNil(s.attribute(.backgroundColor, at: 0, effectiveRange: nil))
    }

    func test_inlineCodeUsesMonospace() {
        let s = build([.code("ls")])
        let font = s.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.traitMonoSpace) ?? false)
    }

    func test_mentionCarriesInternalLinkAndAccentColor() {
        let s = build([.mention(name: "alice", instance: "lemmy.world")])
        XCTAssertTrue(s.string.contains("alice"))
        let url = s.attribute(.link, at: s.length - 1, effectiveRange: nil) as? URL
        XCTAssertEqual(url?.scheme, "spud-markdown")
    }

    func test_superscriptRaised() {
        let s = build([.text("x"), .superscript([.text("2")])])
        let offset = s.attribute(.baselineOffset, at: s.length - 1, effectiveRange: nil) as? CGFloat
        XCTAssertNotNil(offset)
        XCTAssertGreaterThan(offset ?? 0, 0)
    }
}
