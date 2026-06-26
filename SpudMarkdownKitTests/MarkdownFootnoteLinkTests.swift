//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudMarkdownKit

struct MarkdownFootnoteLinkTests {
    @Test
    func definitionRoundTrips() {
        let url = MarkdownFootnoteLink.url(.toDefinition(label: "3"))
        #expect(MarkdownFootnoteLink(url) == .toDefinition(label: "3"))
    }

    @Test
    func referenceRoundTrips() {
        let url = MarkdownFootnoteLink.url(.toReference(label: "note-a"))
        #expect(MarkdownFootnoteLink(url) == .toReference(label: "note-a"))
    }

    @Test
    func definitionAndReferenceURLsDiffer() {
        #expect(
            MarkdownFootnoteLink.url(.toDefinition(label: "1")) !=
                MarkdownFootnoteLink.url(.toReference(label: "1"))
        )
    }

    @Test
    func rejectsNonFootnoteURLs() throws {
        #expect(try MarkdownFootnoteLink(#require(URL(string: "https://example.com"))) == nil)
        #expect(try MarkdownFootnoteLink(#require(URL(string: "spud-markdown://mention?name=a&instance=b"))) == nil)
    }
}
