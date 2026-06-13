//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import XCTest
@testable import SpudUtilKit

class URLCanonicalHostTests: XCTestCase {
    func test_stripsLeadingWww() {
        XCTAssertEqual(URL(string: "https://www.google.com")?.canonicalHost, "google.com")
        XCTAssertEqual(URL(string: "https://www.thesun.co.uk/article")?.canonicalHost, "thesun.co.uk")
    }

    func test_stripsWwwCaseInsensitively() {
        XCTAssertEqual(URL(string: "https://WWW.Example.com")?.canonicalHost, "Example.com")
    }

    func test_passesThroughHostWithoutWww() {
        XCTAssertEqual(URL(string: "https://mozilla.org")?.canonicalHost, "mozilla.org")
        XCTAssertEqual(URL(string: "https://theverge.com/2026/a/b")?.canonicalHost, "theverge.com")
    }

    func test_doesNotStripWwwWithoutDot() {
        // "www" must be its own label (followed by a dot) to be stripped.
        XCTAssertEqual(URL(string: "https://wwwsomething.com")?.canonicalHost, "wwwsomething.com")
    }

    func test_returnsNilWhenNoHost() {
        XCTAssertNil(URL(string: "mailto:someone@example.com")?.canonicalHost)
    }
}
