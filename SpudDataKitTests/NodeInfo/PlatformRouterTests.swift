//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudDataKit

private struct StubNodeInfoService: NodeInfoServiceType {
    let detection: NodeInfoDetection
    func detect(host: String, maxAge: TimeInterval) async -> NodeInfoDetection {
        detection
    }
}

struct PlatformRouterTests {
    @Test
    func lemmyAllowsBothPurposes() async {
        let router = PlatformRouter(nodeInfoService: StubNodeInfoService(detection: .known(.lemmy, version: "0.19.5")))
        #expect(await router.evaluateHomeConnection(host: "lemmy.world", purpose: .login) == .allow)
        #expect(await router.evaluateHomeConnection(host: "lemmy.world", purpose: .register) == .allow)
    }

    @Test
    func nonLemmyBlocksBothPurposes() async {
        let router = PlatformRouter(nodeInfoService: StubNodeInfoService(detection: .known(.mbin, version: "1.0")))
        #expect(
            await router.evaluateHomeConnection(host: "kbin.example", purpose: .login)
                == .block(software: .mbin, displayName: "Mbin", version: "1.0")
        )
        #expect(
            await router.evaluateHomeConnection(host: "kbin.example", purpose: .register)
                == .block(software: .mbin, displayName: "Mbin", version: "1.0")
        )
    }

    /// PieFed speaks the Lemmy-compatible dialect, so login is allowed; but
    /// account creation is web-only, so registration is still blocked.
    @Test
    func piefedAllowsLoginBlocksRegister() async {
        let router = PlatformRouter(nodeInfoService: StubNodeInfoService(detection: .known(.piefed, version: "1.0")))
        #expect(await router.evaluateHomeConnection(host: "piefed.social", purpose: .login) == .allow)
        #expect(
            await router.evaluateHomeConnection(host: "piefed.social", purpose: .register)
                == .block(software: .piefed, displayName: "PieFed", version: "1.0")
        )
    }

    @Test
    func unknownAllowsFailOpen() async {
        let router = PlatformRouter(nodeInfoService: StubNodeInfoService(detection: .unknown))
        #expect(await router.evaluateHomeConnection(host: "waf.example", purpose: .login) == .allow)
        #expect(await router.evaluateHomeConnection(host: "waf.example", purpose: .register) == .allow)
    }
}
