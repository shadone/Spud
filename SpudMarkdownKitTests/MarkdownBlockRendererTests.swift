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
}
