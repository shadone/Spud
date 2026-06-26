//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudUtilKit

struct HTTPSUpgradeStepTests {
    private func upgraded(_ string: String) -> String? {
        guard let url = URL(string: string) else { return nil }
        return HTTPSUpgradeStep().apply(url, config: .default).absoluteString
    }

    @Test
    func upgradesHTTPToHTTPS() {
        #expect(upgraded("http://example.com/path?q=1") == "https://example.com/path?q=1")
    }

    @Test
    func leavesHTTPSUnchanged() {
        #expect(upgraded("https://example.com") == "https://example.com")
    }

    @Test
    func skipsLocalhostAndIPAndOnion() {
        #expect(upgraded("http://localhost:8080/x") == "http://localhost:8080/x")
        #expect(upgraded("http://127.0.0.1/x") == "http://127.0.0.1/x")
        #expect(upgraded("http://[::1]/x") == "http://[::1]/x")
        #expect(upgraded("http://abcdefghij.onion/x") == "http://abcdefghij.onion/x")
    }

    @Test
    func leavesNonHTTPSchemesUnchanged() {
        #expect(upgraded("mailto:jack@example.com") == "mailto:jack@example.com")
        #expect(upgraded("ftp://example.com/file") == "ftp://example.com/file")
    }

    @Test
    func doesNotUpgradeWhenDisabled() throws {
        var config = URLSanitizerConfig.default
        config.upgradeToHTTPS = false
        let url = try #require(URL(string: "http://example.com/path"))
        #expect(HTTPSUpgradeStep().apply(url, config: config).absoluteString == "http://example.com/path")
    }
}
