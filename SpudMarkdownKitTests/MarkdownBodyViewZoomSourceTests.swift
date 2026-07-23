//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
import UIKit
@testable import SpudMarkdownKit

@MainActor
struct MarkdownBodyViewZoomSourceTests {
    private func makeBody(markdown: String) -> MarkdownBodyView {
        let view = MarkdownBodyView(context: MarkdownContext(kind: .post))
        // MarkdownBlockCache lives in the app target (a thin cache in front of
        // MarkdownParser.parse); SpudMarkdownKit must not depend on the app, so
        // this test parses directly, matching MarkdownBodyViewTests.
        view.setBlocks(MarkdownParser.parse(markdown))
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 2000)
        view.layoutIfNeeded()
        return view
    }

    @Test
    func returnsNilWhenNoImageRendered() throws {
        let body = makeBody(markdown: "Just some **text**, no images.")
        #expect(try body.zoomSourceView(forImageURL: #require(URL(string: "https://e.com/a.jpg"))) == nil)
    }

    @Test
    func returnsNilForUnloadedOrMismatchedURL() throws {
        // An image block that never loaded a displayable image is not a valid
        // zoom source (only the loaded state is tappable).
        let url = try #require(URL(string: "https://e.com/pic.jpg"))
        let body = makeBody(markdown: "![alt](\(url.absoluteString))")
        // Not driven to a loaded state in a unit test -> nil.
        #expect(body.zoomSourceView(forImageURL: url) == nil)
        // A URL that isn't in the body -> nil regardless.
        #expect(try body.zoomSourceView(forImageURL: #require(URL(string: "https://e.com/other.jpg"))) == nil)
    }
}
