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
    private func makeService(detection: NodeInfoDetection) throws -> AccountService {
        try AccountService(
            appDatabase: AppDatabase.inMemory(),
            nodeInfoService: StubNodeInfoService(detection: detection)
        )
    }

    /// A genuinely non-Lemmy host (one that does not speak the API at all) is
    /// blocked for both login and registration.
    @Test
    func blocksNonLemmyHostForBothPurposes() async throws {
        let service = try makeService(detection: .known(.mbin, version: "1.0"))
        await #expect(throws: PlatformUnsupportedError.self) {
            try await service.preflightHomeConnection(host: "kbin.example", purpose: .login)
        }
        await #expect(throws: PlatformUnsupportedError.self) {
            try await service.preflightHomeConnection(host: "kbin.example", purpose: .register)
        }
    }

    /// PieFed speaks the Lemmy-compatible dialect, so login is allowed; account
    /// creation is web-only, so registration is still blocked.
    @Test
    func allowsPiefedLoginBlocksPiefedRegister() async throws {
        let service = try makeService(detection: .known(.piefed, version: "1.0"))
        try await service.preflightHomeConnection(host: "piefed.social", purpose: .login)
        await #expect(throws: PlatformUnsupportedError.self) {
            try await service.preflightHomeConnection(host: "piefed.social", purpose: .register)
        }
    }

    @Test
    func allowsLemmyHost() async throws {
        let service = try makeService(detection: .known(.lemmy, version: "0.19.5"))
        try await service.preflightHomeConnection(host: "lemmy.world", purpose: .login)
        try await service.preflightHomeConnection(host: "lemmy.world", purpose: .register)
    }

    @Test
    func allowsUnknownHostFailOpen() async throws {
        let service = try makeService(detection: .unknown)
        try await service.preflightHomeConnection(host: "waf.example", purpose: .login)
        try await service.preflightHomeConnection(host: "waf.example", purpose: .register)
    }
}
