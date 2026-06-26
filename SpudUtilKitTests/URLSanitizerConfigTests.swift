//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudUtilKit

struct URLSanitizerConfigTests {
    @Test
    func default_safeStepsOn_frontEndsOff() {
        let config = URLSanitizerConfig.default
        #expect(config.isEnabled)
        #expect(config.stripTrackingParams)
        #expect(config.unwrapRedirectors)
        #expect(config.upgradeToHTTPS)
        #expect(config.deAMP)
        #expect(!(config.redirectToFrontEnds))
        #expect(config.frontEnds.count == FrontEndService.allCases.count)
        #expect(config.frontEnds.allSatisfy { !$0.isEnabled })
    }

    @Test
    func default_frontEndHostsMatchCatalog() {
        let config = URLSanitizerConfig.default
        #expect(config.setting(for: .twitter).host == "xcancel.com")
        #expect(config.setting(for: .youtube).host == "yewtu.be")
        #expect(config.setting(for: .reddit).host == "redlib.catsarch.com")
        #expect(config.setting(for: .imgur).host == "rimgo.app")
    }

    @Test
    func settingFor_fallsBackToCatalogDefaultWhenMissing() {
        var config = URLSanitizerConfig.default
        config.frontEnds = [] // simulate an older stored config missing entries
        let twitter = config.setting(for: .twitter)
        #expect(twitter.host == "xcancel.com")
        #expect(!(twitter.isEnabled))
    }

    @Test
    func codableRoundTrip() throws {
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
        #expect(decoded == config)
        #expect(decoded.setting(for: .youtube).host == "invidious.example")
        #expect(decoded.setting(for: .youtube).isEnabled)
    }
}
