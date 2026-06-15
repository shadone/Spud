//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import XCTest
@testable import SpudUtilKit

final class RedirectorUnwrapStepTests: XCTestCase {
    private func unwrapped(_ string: String) -> String? {
        guard let url = URL(string: string) else { return nil }
        return RedirectorUnwrapStep().apply(url, config: .default).absoluteString
    }

    func test_unwrapsGoogleRedirect() {
        XCTAssertEqual(
            unwrapped("https://www.google.com/url?q=https://example.com/article&sa=D"),
            "https://example.com/article"
        )
    }

    func test_unwrapsFacebookRedirect() {
        XCTAssertEqual(
            unwrapped("https://l.facebook.com/l.php?u=https%3A%2F%2Fexample.com%2Fx&h=AB"),
            "https://example.com/x"
        )
    }

    func test_recursesThroughNestedWrappers() {
        let inner = "https://example.com/final"
        let middle = "https://l.facebook.com/l.php?u=\(inner.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)"
        let outer = "https://www.google.com/url?q=\(middle.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)"
        XCTAssertEqual(unwrapped(outer), inner)
    }

    func test_leavesNonWrapperUnchanged() {
        XCTAssertEqual(unwrapped("https://example.com/url?q=notaurl"), "https://example.com/url?q=notaurl")
    }

    func test_leavesWrapperWithNonHTTPTargetUnchanged() {
        XCTAssertEqual(
            unwrapped("https://www.google.com/url?q=javascript:alert(1)"),
            "https://www.google.com/url?q=javascript:alert(1)"
        )
    }

    func test_unwrapsRedditOutbound() {
        XCTAssertEqual(
            unwrapped("https://out.reddit.com/?url=https%3A%2F%2Fexample.com%2Fx"),
            "https://example.com/x"
        )
    }

    func test_unwrapsSteamLinkfilter() {
        XCTAssertEqual(
            unwrapped("https://steamcommunity.com/linkfilter/?url=https%3A%2F%2Fexample.com"),
            "https://example.com"
        )
    }

    func test_unwrapsLmFacebook() {
        XCTAssertEqual(
            unwrapped("https://lm.facebook.com/l.php?u=https%3A%2F%2Fexample.com%2Fy"),
            "https://example.com/y"
        )
    }

    func test_doesNotUnwrapWhenDisabled() throws {
        var config = URLSanitizerConfig.default
        config.unwrapRedirectors = false
        let url = try XCTUnwrap(URL(string: "https://www.google.com/url?q=https://example.com/article"))
        XCTAssertEqual(
            RedirectorUnwrapStep().apply(url, config: config).absoluteString,
            "https://www.google.com/url?q=https://example.com/article"
        )
    }
}
