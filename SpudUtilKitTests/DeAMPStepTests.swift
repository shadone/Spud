//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import XCTest
@testable import SpudUtilKit

final class DeAMPStepTests: XCTestCase {
    private func deamped(_ string: String) -> String? {
        guard let url = URL(string: string) else { return nil }
        return DeAMPStep().apply(url, config: .default).absoluteString
    }

    func test_reconstructsCdnAmpProjectURL() {
        XCTAssertEqual(
            deamped("https://www-example-com.cdn.ampproject.org/c/s/www.example.com/article"),
            "https://www.example.com/article"
        )
    }

    func test_reconstructsCdnAmpProjectHTTPVariant() {
        // /c/ (no /s/) denotes an http origin.
        XCTAssertEqual(
            deamped("https://example-com.cdn.ampproject.org/c/example.com/page"),
            "http://example.com/page"
        )
    }

    func test_stripsAmpQueryFlag() {
        XCTAssertEqual(deamped("https://example.com/article?amp=1"), "https://example.com/article")
        XCTAssertEqual(deamped("https://example.com/a?amp=1&id=2"), "https://example.com/a?id=2")
    }

    func test_leavesNonAmpUnchanged() {
        XCTAssertEqual(deamped("https://example.com/amp/guide"), "https://example.com/amp/guide")
        XCTAssertEqual(deamped("https://amp.example.com/x"), "https://amp.example.com/x")
    }
}
