// SpudDataKitTests/NodeInfo/PlatformRouterTests.swift
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
    func lemmyAllows() async {
        let router = PlatformRouter(nodeInfoService: StubNodeInfoService(detection: .known(.lemmy, version: "0.19.5")))
        #expect(await router.evaluateHomeConnection(host: "lemmy.world") == .allow)
    }

    @Test
    func nonLemmyBlocks() async {
        let router = PlatformRouter(nodeInfoService: StubNodeInfoService(detection: .known(.piefed, version: "1.0")))
        #expect(
            await router.evaluateHomeConnection(host: "piefed.social")
                == .block(software: .piefed, displayName: "PieFed", version: "1.0")
        )
    }

    @Test
    func unknownAllowsFailOpen() async {
        let router = PlatformRouter(nodeInfoService: StubNodeInfoService(detection: .unknown))
        #expect(await router.evaluateHomeConnection(host: "waf.example") == .allow)
    }
}
