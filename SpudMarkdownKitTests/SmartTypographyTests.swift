//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
@testable import SpudMarkdownKit

struct SmartTypographyTests {
    @Test
    func dashesAndEllipsis() {
        #expect(SmartTypography.apply("en--dash em---dash ...") == "en\u{2013}dash em\u{2014}dash \u{2026}")
    }

    @Test
    func symbols() {
        #expect(SmartTypography.apply("(c) (tm) (r)") == "\u{00A9} \u{2122} \u{00AE}")
    }

    @Test
    func doubleQuotes() {
        #expect(SmartTypography.apply("\"smart quotes,\"") == "\u{201C}smart quotes,\u{201D}")
    }

    @Test
    func apostrophe() {
        #expect(SmartTypography.apply("don't") == "don\u{2019}t")
    }
}
