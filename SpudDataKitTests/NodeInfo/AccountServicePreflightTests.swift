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

@MainActor
struct AccountServicePreflightTests {
    @Test
    func blocksNonLemmyHost() async throws {
        let service = try AccountService(
            appDatabase: AppDatabase.inMemory(),
            nodeInfoService: StubNodeInfoService(detection: .known(.piefed, version: "1.0"))
        )
        await #expect(throws: PlatformUnsupportedError.self) {
            try await service.preflightHomeConnection(host: "piefed.social")
        }
    }

    @Test
    func allowsLemmyHost() async throws {
        let service = try AccountService(
            appDatabase: AppDatabase.inMemory(),
            nodeInfoService: StubNodeInfoService(detection: .known(.lemmy, version: "0.19.5"))
        )
        try await service.preflightHomeConnection(host: "lemmy.world")
    }

    @Test
    func allowsUnknownHostFailOpen() async throws {
        let service = try AccountService(
            appDatabase: AppDatabase.inMemory(),
            nodeInfoService: StubNodeInfoService(detection: .unknown)
        )
        try await service.preflightHomeConnection(host: "waf.example")
    }
}
