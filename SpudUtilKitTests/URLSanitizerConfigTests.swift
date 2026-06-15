//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import XCTest
@testable import SpudUtilKit

final class URLSanitizerConfigTests: XCTestCase {
    func test_default_safeStepsOn_frontEndsOff() {
        let config = URLSanitizerConfig.default
        XCTAssertTrue(config.isEnabled)
        XCTAssertTrue(config.stripTrackingParams)
        XCTAssertTrue(config.unwrapRedirectors)
        XCTAssertTrue(config.upgradeToHTTPS)
        XCTAssertTrue(config.deAMP)
        XCTAssertFalse(config.redirectToFrontEnds)
        XCTAssertEqual(config.frontEnds.count, FrontEndService.allCases.count)
        XCTAssertTrue(config.frontEnds.allSatisfy { !$0.isEnabled })
    }

    func test_default_frontEndHostsMatchCatalog() {
        let config = URLSanitizerConfig.default
        XCTAssertEqual(config.setting(for: .twitter).host, "xcancel.com")
        XCTAssertEqual(config.setting(for: .youtube).host, "yewtu.be")
        XCTAssertEqual(config.setting(for: .reddit).host, "redlib.catsarch.com")
        XCTAssertEqual(config.setting(for: .imgur).host, "rimgo.app")
    }

    func test_settingFor_fallsBackToCatalogDefaultWhenMissing() {
        var config = URLSanitizerConfig.default
        config.frontEnds = [] // simulate an older stored config missing entries
        let twitter = config.setting(for: .twitter)
        XCTAssertEqual(twitter.host, "xcancel.com")
        XCTAssertFalse(twitter.isEnabled)
    }

    func test_codableRoundTrip() throws {
        var config = URLSanitizerConfig.default
        config.redirectToFrontEnds = true
        config.frontEnds = config.frontEnds.map { entry in
            guard entry.service == .youtube else { return entry }
            var updated = entry
            updated.isEnabled = true
            updated.host = "invidious.example"
            return updated
        }
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(URLSanitizerConfig.self, from: data)
        XCTAssertEqual(decoded, config)
        XCTAssertEqual(decoded.setting(for: .youtube).host, "invidious.example")
        XCTAssertTrue(decoded.setting(for: .youtube).isEnabled)
    }
}
