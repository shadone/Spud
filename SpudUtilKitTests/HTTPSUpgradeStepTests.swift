//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import XCTest
@testable import SpudUtilKit

final class HTTPSUpgradeStepTests: XCTestCase {
    private func upgraded(_ string: String) -> String? {
        guard let url = URL(string: string) else { return nil }
        return HTTPSUpgradeStep().apply(url, config: .default).absoluteString
    }

    func test_upgradesHTTPToHTTPS() {
        XCTAssertEqual(upgraded("http://example.com/path?q=1"), "https://example.com/path?q=1")
    }

    func test_leavesHTTPSUnchanged() {
        XCTAssertEqual(upgraded("https://example.com"), "https://example.com")
    }

    func test_skipsLocalhostAndIPAndOnion() {
        XCTAssertEqual(upgraded("http://localhost:8080/x"), "http://localhost:8080/x")
        XCTAssertEqual(upgraded("http://127.0.0.1/x"), "http://127.0.0.1/x")
        XCTAssertEqual(upgraded("http://[::1]/x"), "http://[::1]/x")
        XCTAssertEqual(upgraded("http://abcdefghij.onion/x"), "http://abcdefghij.onion/x")
    }

    func test_leavesNonHTTPSchemesUnchanged() {
        XCTAssertEqual(upgraded("mailto:jack@example.com"), "mailto:jack@example.com")
        XCTAssertEqual(upgraded("ftp://example.com/file"), "ftp://example.com/file")
    }

    func test_doesNotUpgradeWhenDisabled() throws {
        var config = URLSanitizerConfig.default
        config.upgradeToHTTPS = false
        let url = try XCTUnwrap(URL(string: "http://example.com/path"))
        XCTAssertEqual(HTTPSUpgradeStep().apply(url, config: config).absoluteString, "http://example.com/path")
    }
}
