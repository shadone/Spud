//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudUtilKit

struct URLSanitizerTests {
    private func sanitized(_ string: String, _ config: URLSanitizerConfig) -> String? {
        guard let url = URL(string: string) else { return nil }
        return URLSanitizer.sanitize(url, config: config).absoluteString
    }

    private func allEnabled() -> URLSanitizerConfig {
        var config = URLSanitizerConfig.default
        config.redirectToFrontEnds = true
        config.frontEnds = config.frontEnds.map {
            FrontEndConfig(service: $0.service, isEnabled: true, host: $0.host)
        }
        return config
    }

    @Test
    func masterOff_returnsInputUnchanged() {
        var config = allEnabled()
        config.isEnabled = false
        #expect(sanitized("http://x.com/jack?utm_source=a", config) == "http://x.com/jack?utm_source=a")
    }

    @Test
    func runsStepsInOrder_unwrapThenUpgradeThenStripThenFrontEnd() {
        // Google-wrapped, http, tracker-laden twitter link -> unwrapped,
        // https-upgraded, stripped, then rewritten to xcancel.
        let inner = "http://twitter.com/jack?utm_source=news&s=20"
        let wrapped = "https://www.google.com/url?q=\(inner.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)"
        #expect(sanitized(wrapped, allEnabled()) == "https://xcancel.com/jack?s=20")
    }

    @Test
    func idempotent() throws {
        let config = allEnabled()
        let once = try #require(sanitized("http://x.com/jack?utm_source=a&t=1", config))
        let twiceURL = try #require(URL(string: once))
        let twice = URLSanitizer.sanitize(twiceURL, config: config).absoluteString
        #expect(once == twice)
    }

    @Test
    func defaultConfig_cleansButDoesNotRedirectFrontEnds() {
        // default has front-ends OFF: tracker stripped, host preserved.
        #expect(
            sanitized("https://x.com/jack?utm_source=a", .default) ==
                "https://x.com/jack"
        )
    }
}
