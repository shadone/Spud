//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
import UIKit
@testable import SpudMarkdownKit

@MainActor
struct MarkdownBodyViewTests {
    @Test
    func footnoteTargetsResolveAfterSetBlocks() {
        let body = MarkdownBodyView(context: MarkdownContext(kind: .post))
        body.setBlocks(MarkdownParser.parse("Thanks.[^1]\n\n[^1]: Over wired."))
        #expect(
            body.footnoteTarget(for: MarkdownFootnoteLink.url(.toDefinition(label: "1"))) != nil,
            "tapping the [^1] reference should resolve to its definition row"
        )
        #expect(
            body.footnoteTarget(for: MarkdownFootnoteLink.url(.toReference(label: "1"))) != nil,
            "tapping the definition's return arrow should resolve to the reference"
        )
    }

    @Test
    func realLinkIsNotAFootnoteTarget() throws {
        let body = MarkdownBodyView(context: MarkdownContext(kind: .post))
        body.setBlocks([.paragraph([.text("hi")])])
        #expect(try body.footnoteTarget(for: #require(URL(string: "https://example.com"))) == nil)
    }
}
