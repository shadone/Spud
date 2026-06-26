//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudUtilKit

struct RedirectorUnwrapStepTests {
    private func unwrapped(_ string: String) -> String? {
        guard let url = URL(string: string) else { return nil }
        return RedirectorUnwrapStep().apply(url, config: .default).absoluteString
    }

    @Test
    func unwrapsGoogleRedirect() {
        #expect(
            unwrapped("https://www.google.com/url?q=https://example.com/article&sa=D") ==
                "https://example.com/article"
        )
    }

    @Test
    func unwrapsFacebookRedirect() {
        #expect(
            unwrapped("https://l.facebook.com/l.php?u=https%3A%2F%2Fexample.com%2Fx&h=AB") ==
                "https://example.com/x"
        )
    }

    @Test
    func recursesThroughNestedWrappers() {
        let inner = "https://example.com/final"
        let middle = "https://l.facebook.com/l.php?u=\(inner.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)"
        let outer = "https://www.google.com/url?q=\(middle.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)"
        #expect(unwrapped(outer) == inner)
    }

    @Test
    func leavesNonWrapperUnchanged() {
        #expect(unwrapped("https://example.com/url?q=notaurl") == "https://example.com/url?q=notaurl")
    }

    @Test
    func leavesWrapperWithNonHTTPTargetUnchanged() {
        #expect(
            unwrapped("https://www.google.com/url?q=javascript:alert(1)") ==
                "https://www.google.com/url?q=javascript:alert(1)"
        )
    }

    @Test
    func unwrapsRedditOutbound() {
        #expect(
            unwrapped("https://out.reddit.com/?url=https%3A%2F%2Fexample.com%2Fx") ==
                "https://example.com/x"
        )
    }

    @Test
    func unwrapsSteamLinkfilter() {
        #expect(
            unwrapped("https://steamcommunity.com/linkfilter/?url=https%3A%2F%2Fexample.com") ==
                "https://example.com"
        )
    }

    @Test
    func unwrapsLmFacebook() {
        #expect(
            unwrapped("https://lm.facebook.com/l.php?u=https%3A%2F%2Fexample.com%2Fy") ==
                "https://example.com/y"
        )
    }

    @Test
    func doesNotUnwrapWhenDisabled() throws {
        var config = URLSanitizerConfig.default
        config.unwrapRedirectors = false
        let url = try #require(URL(string: "https://www.google.com/url?q=https://example.com/article"))
        #expect(
            RedirectorUnwrapStep().apply(url, config: config).absoluteString ==
                "https://www.google.com/url?q=https://example.com/article"
        )
    }
}
