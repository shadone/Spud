//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import SpudMarkdownKit

final class MarkdownFootnoteLinkTests: XCTestCase {
    func test_definitionRoundTrips() {
        let url = MarkdownFootnoteLink.url(.toDefinition(label: "3"))
        XCTAssertEqual(MarkdownFootnoteLink(url), .toDefinition(label: "3"))
    }

    func test_referenceRoundTrips() {
        let url = MarkdownFootnoteLink.url(.toReference(label: "note-a"))
        XCTAssertEqual(MarkdownFootnoteLink(url), .toReference(label: "note-a"))
    }

    func test_definitionAndReferenceURLsDiffer() {
        XCTAssertNotEqual(
            MarkdownFootnoteLink.url(.toDefinition(label: "1")),
            MarkdownFootnoteLink.url(.toReference(label: "1"))
        )
    }

    func test_rejectsNonFootnoteURLs() throws {
        XCTAssertNil(try MarkdownFootnoteLink(XCTUnwrap(URL(string: "https://example.com"))))
        XCTAssertNil(try MarkdownFootnoteLink(XCTUnwrap(URL(string: "spud-markdown://mention?name=a&instance=b"))))
    }
}
