//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudUtilKit

struct URLCanonicalHostTests {
    @Test
    func stripsLeadingWww() {
        #expect(URL(string: "https://www.google.com")?.canonicalHost == "google.com")
        #expect(URL(string: "https://www.thesun.co.uk/article")?.canonicalHost == "thesun.co.uk")
    }

    @Test
    func stripsWwwCaseInsensitively() {
        #expect(URL(string: "https://WWW.Example.com")?.canonicalHost == "Example.com")
    }

    @Test
    func passesThroughHostWithoutWww() {
        #expect(URL(string: "https://mozilla.org")?.canonicalHost == "mozilla.org")
        #expect(URL(string: "https://theverge.com/2026/a/b")?.canonicalHost == "theverge.com")
    }

    @Test
    func doesNotStripWwwWithoutDot() {
        // "www" must be its own label (followed by a dot) to be stripped.
        #expect(URL(string: "https://wwwsomething.com")?.canonicalHost == "wwwsomething.com")
    }

    @Test
    func returnsNilWhenNoHost() {
        #expect(URL(string: "mailto:someone@example.com")?.canonicalHost == nil)
    }
}
