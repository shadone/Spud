//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import XCTest
@testable import SpudUtilKit

final class FrontEndRewriteStepTests: XCTestCase {
    /// A config with every front-end enabled at its catalog default host.
    private func allEnabled() -> URLSanitizerConfig {
        var config = URLSanitizerConfig.default
        config.redirectToFrontEnds = true
        config.frontEnds = config.frontEnds.map {
            FrontEndConfig(service: $0.service, isEnabled: true, host: $0.host)
        }
        return config
    }

    private func rewritten(_ string: String, _ config: URLSanitizerConfig) -> String? {
        guard let url = URL(string: string) else { return nil }
        return FrontEndRewriteStep().apply(url, config: config).absoluteString
    }

    func test_rewritesTwitterAndXIncludingSubdomains() {
        let c = allEnabled()
        XCTAssertEqual(rewritten("https://twitter.com/jack/status/20", c), "https://xcancel.com/jack/status/20")
        XCTAssertEqual(rewritten("https://x.com/jack", c), "https://xcancel.com/jack")
        XCTAssertEqual(rewritten("https://mobile.twitter.com/jack", c), "https://xcancel.com/jack")
        XCTAssertEqual(rewritten("https://www.x.com/jack", c), "https://xcancel.com/jack")
    }

    func test_rewritesYouTubeRedditImgur() {
        let c = allEnabled()
        XCTAssertEqual(rewritten("https://youtu.be/abc?t=5", c), "https://yewtu.be/abc?t=5")
        XCTAssertEqual(rewritten("https://www.youtube.com/watch?v=abc", c), "https://yewtu.be/watch?v=abc")
        XCTAssertEqual(rewritten("https://reddit.com/r/swift", c), "https://redlib.catsarch.com/r/swift")
        XCTAssertEqual(rewritten("https://imgur.com/gallery/x", c), "https://rimgo.app/gallery/x")
    }

    func test_usesUserOverriddenHost() {
        var c = allEnabled()
        c.frontEnds = c.frontEnds.map { entry in
            guard entry.service == .twitter else { return entry }
            return FrontEndConfig(service: .twitter, isEnabled: true, host: "nitter.example")
        }
        XCTAssertEqual(rewritten("https://x.com/jack", c), "https://nitter.example/jack")
    }

    func test_doesNotRewriteWhenCategoryMasterOff() {
        var c = allEnabled()
        c.redirectToFrontEnds = false
        XCTAssertEqual(rewritten("https://x.com/jack", c), "https://x.com/jack")
    }

    func test_doesNotRewriteWhenServiceDisabled() {
        var c = allEnabled()
        c.frontEnds = c.frontEnds.map { entry in
            guard entry.service == .twitter else { return entry }
            return FrontEndConfig(service: .twitter, isEnabled: false, host: entry.host)
        }
        XCTAssertEqual(rewritten("https://x.com/jack", c), "https://x.com/jack")
    }

    func test_leavesUnlistedSubdomainsAndLookalikesUnchanged() {
        let c = allEnabled()
        XCTAssertEqual(rewritten("https://api.twitter.com/2/tweets", c), "https://api.twitter.com/2/tweets")
        XCTAssertEqual(rewritten("https://notx.com/jack", c), "https://notx.com/jack")
        XCTAssertEqual(rewritten("https://mozilla.org/x.com", c), "https://mozilla.org/x.com")
    }

    func test_isCaseInsensitiveOnHost() {
        let c = allEnabled()
        XCTAssertEqual(rewritten("https://Twitter.com/jack", c), "https://xcancel.com/jack")
    }

    func test_returnsSelfWhenNoHost() {
        let c = allEnabled()
        XCTAssertEqual(rewritten("mailto:jack@twitter.com", c), "mailto:jack@twitter.com")
    }
}
