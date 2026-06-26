//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudUtilKit

struct FrontEndRewriteStepTests {
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

    @Test
    func rewritesTwitterAndXIncludingSubdomains() {
        let c = allEnabled()
        #expect(rewritten("https://twitter.com/jack/status/20", c) == "https://xcancel.com/jack/status/20")
        #expect(rewritten("https://x.com/jack", c) == "https://xcancel.com/jack")
        #expect(rewritten("https://mobile.twitter.com/jack", c) == "https://xcancel.com/jack")
        #expect(rewritten("https://www.x.com/jack", c) == "https://xcancel.com/jack")
    }

    @Test
    func rewritesYouTubeRedditImgur() {
        let c = allEnabled()
        #expect(rewritten("https://youtu.be/abc?t=5", c) == "https://yewtu.be/abc?t=5")
        #expect(rewritten("https://www.youtube.com/watch?v=abc", c) == "https://yewtu.be/watch?v=abc")
        #expect(rewritten("https://reddit.com/r/swift", c) == "https://redlib.catsarch.com/r/swift")
        #expect(rewritten("https://imgur.com/gallery/x", c) == "https://rimgo.app/gallery/x")
    }

    @Test
    func usesUserOverriddenHost() {
        var c = allEnabled()
        c.frontEnds = c.frontEnds.map { entry in
            guard entry.service == .twitter else { return entry }
            return FrontEndConfig(service: .twitter, isEnabled: true, host: "nitter.example")
        }
        #expect(rewritten("https://x.com/jack", c) == "https://nitter.example/jack")
    }

    @Test
    func doesNotRewriteWhenCategoryMasterOff() {
        var c = allEnabled()
        c.redirectToFrontEnds = false
        #expect(rewritten("https://x.com/jack", c) == "https://x.com/jack")
    }

    @Test
    func doesNotRewriteWhenServiceDisabled() {
        var c = allEnabled()
        c.frontEnds = c.frontEnds.map { entry in
            guard entry.service == .twitter else { return entry }
            return FrontEndConfig(service: .twitter, isEnabled: false, host: entry.host)
        }
        #expect(rewritten("https://x.com/jack", c) == "https://x.com/jack")
    }

    @Test
    func leavesUnlistedSubdomainsAndLookalikesUnchanged() {
        let c = allEnabled()
        #expect(rewritten("https://api.twitter.com/2/tweets", c) == "https://api.twitter.com/2/tweets")
        #expect(rewritten("https://notx.com/jack", c) == "https://notx.com/jack")
        #expect(rewritten("https://mozilla.org/x.com", c) == "https://mozilla.org/x.com")
    }

    @Test
    func isCaseInsensitiveOnHost() {
        let c = allEnabled()
        #expect(rewritten("https://Twitter.com/jack", c) == "https://xcancel.com/jack")
    }

    @Test
    func returnsSelfWhenNoHost() {
        let c = allEnabled()
        #expect(rewritten("mailto:jack@twitter.com", c) == "mailto:jack@twitter.com")
    }
}
