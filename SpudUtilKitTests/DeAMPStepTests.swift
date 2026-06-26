//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudUtilKit

struct DeAMPStepTests {
    private func deamped(_ string: String) -> String? {
        guard let url = URL(string: string) else { return nil }
        return DeAMPStep().apply(url, config: .default).absoluteString
    }

    @Test
    func reconstructsCdnAmpProjectURL() {
        #expect(
            deamped("https://www-example-com.cdn.ampproject.org/c/s/www.example.com/article") ==
                "https://www.example.com/article"
        )
    }

    @Test
    func reconstructsCdnAmpProjectHTTPVariant() {
        // /c/ (no /s/) denotes an http origin.
        #expect(
            deamped("https://example-com.cdn.ampproject.org/c/example.com/page") ==
                "http://example.com/page"
        )
    }

    @Test
    func stripsAmpQueryFlag() {
        #expect(deamped("https://example.com/article?amp=1") == "https://example.com/article")
        #expect(deamped("https://example.com/a?amp=1&id=2") == "https://example.com/a?id=2")
    }

    @Test
    func leavesNonAmpUnchanged() {
        #expect(deamped("https://example.com/amp/guide") == "https://example.com/amp/guide")
        #expect(deamped("https://amp.example.com/x") == "https://amp.example.com/x")
    }

    @Test
    func doesNotDeAmpWhenDisabled() throws {
        var config = URLSanitizerConfig.default
        config.deAMP = false
        let url = try #require(URL(string: "https://example.com/article?amp=1"))
        #expect(DeAMPStep().apply(url, config: config).absoluteString == "https://example.com/article?amp=1")
    }
}
