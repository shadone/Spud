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

    @Test
    func setBlocksWithEqualBlocksKeepsBlockViews() {
        let body = MarkdownBodyView(context: MarkdownContext(kind: .comment))
        let source = "Hello **world**.\n\n![a cat](https://example.com/cat.png)"
        body.setBlocks(MarkdownParser.parse(source))
        let before = blockViews(of: body).map(ObjectIdentifier.init)
        #expect(!before.isEmpty, "first setBlocks must render block views")

        // A fresh-but-equal array (a separate parse of the same source) must be a
        // no-op: rebuilding resets every ImageBlockView to its loading placeholder,
        // which renders for at least one frame even on a memory-cache hit.
        body.setBlocks(MarkdownParser.parse(source))
        let after = blockViews(of: body).map(ObjectIdentifier.init)
        #expect(after == before, "equal blocks must keep the same block view instances")
    }

    @Test
    func setBlocksWithDifferentBlocksRebuilds() {
        let body = MarkdownBodyView(context: MarkdownContext(kind: .comment))
        body.setBlocks(MarkdownParser.parse("First body."))
        let before = blockViews(of: body).map(ObjectIdentifier.init)

        body.setBlocks(MarkdownParser.parse("Second body.\n\nWith another paragraph."))
        let after = blockViews(of: body).map(ObjectIdentifier.init)
        #expect(after != before, "changed blocks must rebuild the block views")
        #expect(after.count == 2)
    }

    @Test
    func setBlocksAfterEmptyApplies() {
        let body = MarkdownBodyView(context: MarkdownContext(kind: .comment))
        let blocks = MarkdownParser.parse("Collapsed, then expanded.")
        body.setBlocks(blocks)
        body.setBlocks([])
        #expect(blockViews(of: body).isEmpty, "setBlocks([]) must clear the rendered content")

        body.setBlocks(blocks)
        #expect(!blockViews(of: body).isEmpty, "re-applying blocks after a clear must render them")
    }

    /// The rendered block views. The stack is a private implementation detail, so
    /// walk the view hierarchy: the body's first (and only) subview is the stack.
    private func blockViews(of body: MarkdownBodyView) -> [UIView] {
        guard let stack = body.subviews.first as? UIStackView else { return [] }
        return stack.arrangedSubviews
    }
}
