//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import XCTest
@testable import SpudUtilKit

final class URLSanitizerTests: XCTestCase {
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

    func test_masterOff_returnsInputUnchanged() {
        var config = allEnabled()
        config.isEnabled = false
        XCTAssertEqual(sanitized("http://x.com/jack?utm_source=a", config), "http://x.com/jack?utm_source=a")
    }

    func test_runsStepsInOrder_unwrapThenUpgradeThenStripThenFrontEnd() {
        // Google-wrapped, http, tracker-laden twitter link -> unwrapped,
        // https-upgraded, stripped, then rewritten to xcancel.
        let inner = "http://twitter.com/jack?utm_source=news&s=20"
        let wrapped = "https://www.google.com/url?q=\(inner.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)"
        XCTAssertEqual(sanitized(wrapped, allEnabled()), "https://xcancel.com/jack?s=20")
    }

    func test_idempotent() throws {
        let config = allEnabled()
        let once = try XCTUnwrap(sanitized("http://x.com/jack?utm_source=a&t=1", config))
        let twiceURL = try XCTUnwrap(URL(string: once))
        let twice = URLSanitizer.sanitize(twiceURL, config: config).absoluteString
        XCTAssertEqual(once, twice)
    }

    func test_defaultConfig_cleansButDoesNotRedirectFrontEnds() {
        // default has front-ends OFF: tracker stripped, host preserved.
        XCTAssertEqual(
            sanitized("https://x.com/jack?utm_source=a", .default),
            "https://x.com/jack"
        )
    }
}
