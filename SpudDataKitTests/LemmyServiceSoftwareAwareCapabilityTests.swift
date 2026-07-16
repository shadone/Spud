//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import HTTPTypes
import LemmyKit
import OpenAPIRuntime
import Testing
@testable import SpudDataKit

// MARK: - Stub transport

/// `LemmyService.instanceCapabilities()` resolves purely from persisted state
/// (account -> site -> NodeInfo cache), so a network call reaching this stub
/// would mean the resolution accidentally started hitting the wire.
private final class UnreachedTransport: ClientTransport, @unchecked Sendable {
    func send(
        _: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID _: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        Issue.record("instanceCapabilities() must not make a network request")
        throw URLError(.unknown)
    }
}

// MARK: - Tests

/// Covers `LemmyService.instanceCapabilities()` (Task 8) resolving
/// software-aware capabilities from the account host's `NodeInfoCacheRecord` --
/// the same signal `AccountService.instanceCapabilities(forAccountKeychainId:)`
/// already keys off via its private `isPiefed` branch (see
/// `AccountServiceDialectSelectionTests` for that `@MainActor` counterpart).
/// Before this task `LemmyService.instanceCapabilities()` hardcoded
/// `software: .lemmy` unconditionally, so a PieFed account's own
/// service-level gates (`requireCapability`, e.g. behind `uploadImage`) never
/// withheld anything even when NodeInfo had positively identified the host as
/// PieFed.
@MainActor
struct LemmyServiceSoftwareAwareCapabilityTests {
    private static let keychainId = "keychain-software-aware-capability-test"

    /// Seeds instance -> site -> account rows for `host` (mirroring
    /// `LemmyServiceContentNotFoundTests`'s harness) and builds a `LemmyService`
    /// over a transport that fails the test if ever reached. `siteVersion`
    /// seeds `site.version` directly (bypassing a real `getSite` fetch), so a
    /// test can simulate a persisted version string without a network call.
    private func makeService(appDatabase: AppDatabase, host: String, siteVersion: String? = nil) async throws -> LemmyService {
        // Captured into a local `let` before entering the `@Sendable` GRDB
        // closure: `Self.keychainId` is MainActor-isolated (this suite is
        // `@MainActor`), which a `@Sendable` closure cannot reference directly.
        let keychainId = Self.keychainId
        try await appDatabase.writer.write { db in
            var instance = InstanceRecord(actorId: "https://\(host)")
            try instance.insert(db)
            var site = SiteRecord(instanceId: instance.id!)
            site.version = siteVersion
            try site.insert(db)
            var account = AccountRecord(
                siteId: site.id!,
                accountKeychainId: keychainId,
                isSignedOutAccountType: false
            )
            try account.insert(db)
        }

        let api = LemmyApi(
            instanceUrl: URL(string: "https://\(host)")!,
            credential: LemmyCredential(jwt: "fake-jwt"),
            transport: UnreachedTransport()
        )
        return LemmyService(
            accountKeychainId: keychainId,
            accountIsSignedOut: false,
            appDatabase: appDatabase,
            api: api,
            reachability: StaticReachabilityMonitor(isOnline: true)
        )
    }

    @Test
    func piefedNodeInfoCacheWithholdsImageUploadAndServerUserSettings() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let host = "piefed.example"
        try appDatabase.seedNodeInfoCacheForUITests(host: host, softwareName: "piefed", softwareVersion: "1.7.5")
        let service = try await makeService(appDatabase: appDatabase, host: host)

        let capabilities = await service.instanceCapabilities()
        #expect(!capabilities.can(.imageUpload))
        #expect(!capabilities.can(.serverUserSettings))
        // The gap is exactly those two — everything else stays available.
        #expect(capabilities.can(.inbox))
        #expect(capabilities.can(.personProfiles))
        #expect(capabilities.can(.privateMessages))
        #expect(capabilities.can(.hidePosts))
        #expect(capabilities.can(.markPostsRead))
    }

    @Test
    func lemmyNodeInfoCacheKeepsEverythingAvailable() async throws {
        // A host NodeInfo has positively cached as Lemmy (not PieFed) resolves
        // exactly as before this task -- the NodeInfo check only ever
        // short-circuits to `.piefed`, never the reverse.
        let appDatabase = try AppDatabase.inMemory()
        let host = "lemmy.example"
        try appDatabase.seedNodeInfoCacheForUITests(host: host, softwareName: "lemmy", softwareVersion: "0.19.11")
        let service = try await makeService(appDatabase: appDatabase, host: host)

        let capabilities = await service.instanceCapabilities()
        for capability in InstanceCapability.allCases {
            #expect(capabilities.can(capability))
        }
    }

    /// (Task 10, item 3) `instanceCapabilities()` must not parse a PieFed
    /// account's persisted site version as a Lemmy version -- mirroring
    /// `AccountService.instanceCapabilities(forAccountKeychainId:)`'s "don't
    /// parse it on the Lemmy scale" guard. A persisted "1.7.5" is shaped like
    /// a valid Lemmy 1.x version string; if it were fed into the Lemmy
    /// derivation table it would still land on the same withheld set today
    /// (that table currently ignores `version` outright), so this test's real
    /// job is pinning the invariant against a FUTURE version-sensitive Lemmy
    /// table change -- not catching a currently-observable bug.
    @Test
    func piefedSiteVersionNeverAffectsCapabilities() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let host = "piefed-version.example"
        try appDatabase.seedNodeInfoCacheForUITests(host: host, softwareName: "piefed", softwareVersion: "1.7.5")
        let service = try await makeService(appDatabase: appDatabase, host: host, siteVersion: "1.7.5")

        let capabilities = await service.instanceCapabilities()
        #expect(!capabilities.can(.imageUpload))
        #expect(!capabilities.can(.serverUserSettings))
        for capability in InstanceCapability.allCases where capability != .imageUpload && capability != .serverUserSettings {
            #expect(capabilities.can(capability), "expected \(capability) available on PieFed regardless of site version")
        }
    }

    @Test
    func noNodeInfoCacheRowFailsOpenToLemmy() async throws {
        // A host that has never been NodeInfo-probed (e.g. an account added
        // before the probe ran) must fail open exactly like an unprobed host
        // does everywhere else in NodeInfo detection -- never mistaken for a
        // confirmed PieFed gap.
        let appDatabase = try AppDatabase.inMemory()
        let service = try await makeService(appDatabase: appDatabase, host: "never-probed.example")

        let capabilities = await service.instanceCapabilities()
        for capability in InstanceCapability.allCases {
            #expect(capabilities.can(capability))
        }
    }
}
