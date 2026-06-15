//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import SpudMarkdownKit

final class SmartTypographyTests: XCTestCase {
    func test_dashesAndEllipsis() {
        XCTAssertEqual(SmartTypography.apply("en--dash em---dash ..."), "en\u{2013}dash em\u{2014}dash \u{2026}")
    }

    func test_symbols() {
        XCTAssertEqual(SmartTypography.apply("(c) (tm) (r)"), "\u{00A9} \u{2122} \u{00AE}")
    }

    func test_doubleQuotes() {
        XCTAssertEqual(SmartTypography.apply("\"smart quotes,\""), "\u{201C}smart quotes,\u{201D}")
    }

    func test_apostrophe() {
        XCTAssertEqual(SmartTypography.apply("don't"), "don\u{2019}t")
    }
}
