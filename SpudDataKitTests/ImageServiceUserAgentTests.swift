//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import SpudDataKit

final class ImageServiceUserAgentTests: XCTestCase {
    func test_userAgent_identifiesTheApp() {
        XCTAssertTrue(
            ImageService.userAgent.hasPrefix("Spud/"),
            "expected a `Spud/<version>` user-agent, got \(ImageService.userAgent)"
        )
    }

    func test_userAgent_hasNoCFNetworkToken() {
        // The whole point: iOS' default `CFNetwork/...` token is denylisted by
        // some Lemmy instances' nginx, which 403s every image request.
        XCTAssertFalse(
            ImageService.userAgent.contains("CFNetwork"),
            "user-agent must not contain the denylisted CFNetwork token"
        )
    }
}
