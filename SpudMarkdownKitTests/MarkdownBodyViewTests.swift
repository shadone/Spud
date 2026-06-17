//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit
import XCTest
@testable import SpudMarkdownKit

@MainActor
final class MarkdownBodyViewTests: XCTestCase {
    func test_footnoteTargetsResolveAfterSetBlocks() {
        let body = MarkdownBodyView(context: MarkdownContext(kind: .post))
        body.setBlocks(MarkdownParser.parse("Thanks.[^1]\n\n[^1]: Over wired."))
        XCTAssertNotNil(
            body.footnoteTarget(for: MarkdownFootnoteLink.url(.toDefinition(label: "1"))),
            "tapping the [^1] reference should resolve to its definition row"
        )
        XCTAssertNotNil(
            body.footnoteTarget(for: MarkdownFootnoteLink.url(.toReference(label: "1"))),
            "tapping the definition's return arrow should resolve to the reference"
        )
    }

    func test_realLinkIsNotAFootnoteTarget() throws {
        let body = MarkdownBodyView(context: MarkdownContext(kind: .post))
        body.setBlocks([.paragraph([.text("hi")])])
        XCTAssertNil(try body.footnoteTarget(for: XCTUnwrap(URL(string: "https://example.com"))))
    }
}
