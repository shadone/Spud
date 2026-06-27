//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
@testable import SpudDataKit

struct AppUserAgentTests {
    @Test
    func value_identifiesTheApp() {
        #expect(
            AppUserAgent.value.hasPrefix("Spud/"),
            "expected a `Spud/<version>` user-agent, got \(AppUserAgent.value)"
        )
    }

    @Test
    func value_hasNoCFNetworkToken() {
        // The whole point: iOS' default `CFNetwork/...` token is denylisted by
        // some Lemmy instances' nginx, which 403s every request that carries it.
        #expect(
            !(AppUserAgent.value.contains("CFNetwork")),
            "user-agent must not contain the denylisted CFNetwork token"
        )
    }
}
