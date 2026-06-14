//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import SpudDataKit

final class AppUserAgentTests: XCTestCase {
    func test_value_identifiesTheApp() {
        XCTAssertTrue(
            AppUserAgent.value.hasPrefix("Spud/"),
            "expected a `Spud/<version>` user-agent, got \(AppUserAgent.value)"
        )
    }

    func test_value_hasNoCFNetworkToken() {
        // The whole point: iOS' default `CFNetwork/...` token is denylisted by
        // some Lemmy instances' nginx, which 403s every request that carries it.
        XCTAssertFalse(
            AppUserAgent.value.contains("CFNetwork"),
            "user-agent must not contain the denylisted CFNetwork token"
        )
    }
}
