//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit
import XCTest
@testable import SpudMarkdownKit

@MainActor
final class MarkdownBlockRendererTests: XCTestCase {
    private func renderer() -> MarkdownBlockRenderer {
        MarkdownBlockRenderer(context: MarkdownContext(kind: .post))
    }

    func test_paragraphRendersProseBlockView() {
        let view = renderer().view(for: .paragraph([.text("hi")]))
        XCTAssertTrue(view is ProseBlockView)
    }

    func test_thematicBreakRendersThematicBreakView() {
        XCTAssertTrue(renderer().view(for: .thematicBreak) is ThematicBreakView)
    }

    func test_blockQuoteRendersQuoteBlockView() {
        let view = renderer().view(for: .blockQuote([.paragraph([.text("q")])]))
        XCTAssertTrue(view is QuoteBlockView)
    }

    func test_viewsForBlocksReturnsOnePerBlock() {
        let views = renderer().views(for: [.paragraph([.text("a")]), .thematicBreak])
        XCTAssertEqual(views.count, 2)
    }

    func test_imageRendersImageBlockView() throws {
        let image = try MarkdownImage(url: XCTUnwrap(URL(string: "https://example.com/a.jpg")), altText: "alt")
        XCTAssertTrue(renderer().view(for: .image(image)) is ImageBlockView)
    }

    func test_audioRendersAudioBlockView() throws {
        XCTAssertTrue(try renderer().view(for: .audio(url: XCTUnwrap(URL(string: "https://example.com/a.mp3")))) is AudioBlockView)
    }

    func test_videoRendersVideoBlockView() throws {
        XCTAssertTrue(try renderer().view(for: .video(url: XCTUnwrap(URL(string: "https://example.com/a.mp4")))) is VideoBlockView)
    }

    private func headingText(_ block: MarkdownBlock) throws -> NSAttributedString {
        let view = renderer().view(for: block)
        let prose = try XCTUnwrap(view as? ProseBlockView)
        return try XCTUnwrap(prose.attributedText)
    }

    func test_h6UppercasesAndKeepsLinkTappable() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        let s = try headingText(.heading(level: 6, [.text("see "), .link(text: [.text("docs")], url: url)]))
        XCTAssertEqual(s.string, "SEE DOCS")
        let linkRange = (s.string as NSString).range(of: "DOCS")
        XCTAssertEqual(s.attribute(.link, at: linkRange.location, effectiveRange: nil) as? URL, url)
    }

    func test_h6PreservesItalicRun() throws {
        let s = try headingText(.heading(level: 6, [.text("a "), .emphasis([.text("b")])]))
        XCTAssertEqual(s.string, "A B")
        let italicRange = (s.string as NSString).range(of: "B")
        let font = s.attribute(.font, at: italicRange.location, effectiveRange: nil) as? UIFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.traitItalic) ?? false, "italic run lost in H6")
    }
}
