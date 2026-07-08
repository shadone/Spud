//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import SpudUtilKit
import Testing
@testable import Spud

// MARK: - Test doubles

/// Counts `metadata(host:)` calls and returns a fixed result, so a test can prove
/// the browse-instance probe fires only on explicit engagement (never from rail /
/// directory rendering) and exactly once per browse-open.
private actor SpyNodeInfoService: NodeInfoServiceType {
    private(set) var metadataCallCount = 0
    private let result: InstanceMetadata?

    init(result: InstanceMetadata?) {
        self.result = result
    }

    func detect(host _: String, maxAge _: TimeInterval) async -> NodeInfoDetection {
        guard let result else { return .unknown }
        return .known(result.software, version: result.version)
    }

    func metadata(host _: String, maxAge _: TimeInterval) async -> InstanceMetadata? {
        metadataCallCount += 1
        return result
    }
}

/// Minimal container satisfying `DiscoverViewModel.Dependencies` with an injected
/// spy NodeInfo service.
@MainActor
private struct TestDependencies:
    HasAccountService,
    HasAlertService,
    HasAppDatabase,
    HasNodeInfoService,
    HasPreferencesService
{
    let accountService: AccountServiceType
    let alertService: AlertServiceType
    let appDatabase: AppDatabase
    let nodeInfoService: NodeInfoServiceType
    let preferencesService: PreferencesServiceType
}

// MARK: - Tests

/// Verifies the browse-instance header's live-metadata gating on `DiscoverViewModel`:
/// no probe fires from constructing the model or rendering its rails (the privacy
/// boundary), exactly one probe fires per browse-open, and a nil probe result
/// leaves no chip state (fail-open).
@MainActor
struct DiscoverViewModelMetadataTests {
    private static let knownMetadata = InstanceMetadata(
        software: .lemmy,
        version: "0.19.11",
        openRegistrations: true,
        usersTotal: nil,
        usersActiveMonth: nil,
        usersActiveHalfyear: nil,
        localPosts: nil,
        localComments: nil
    )

    private func makeViewModel(spy: SpyNodeInfoService) throws -> DiscoverViewModel {
        let appDatabase = try AppDatabase.inMemory()
        let accountService = AccountService(appDatabase: appDatabase)
        let dependencies = TestDependencies(
            accountService: accountService,
            alertService: AlertService(),
            appDatabase: appDatabase,
            nodeInfoService: spy,
            preferencesService: PreferencesService.ephemeral()
        )
        return DiscoverViewModel(
            accountScope: accountService.scope(forAccountKeychainId: "test-signed-out"),
            isSignedIn: false,
            dependencies: dependencies,
            onOpenCommunity: { _ in },
            onOpenPack: { _ in },
            onOpenInstance: { _ in },
            onSeeAllCommunities: { _, _ in },
            onSeeAllInstances: { _, _ in },
            onRequestSignIn: { }
        )
    }

    /// Wait for the async directory observation to fire (rails recompute), so the
    /// "no probe from rendering" assertion covers the render path, not just init.
    private func waitUntilNotLoading(_ viewModel: DiscoverViewModel) async throws {
        let deadline = Date().addingTimeInterval(2)
        while viewModel.isLoading {
            if Date() > deadline { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    @Test
    func railRenderDoesNotProbe_thenOneProbePerBrowseOpen() async throws {
        let spy = SpyNodeInfoService(result: Self.knownMetadata)
        let viewModel = try makeViewModel(spy: spy)

        // Rendering the rails/directory must never probe NodeInfo.
        try await waitUntilNotLoading(viewModel)
        #expect(await spy.metadataCallCount == 0)
        #expect(viewModel.metadata(forHost: "lemmy.world") == nil)

        // Opening an instance browse screen probes exactly once and publishes it.
        await viewModel.loadInstanceMetadata(forHost: "lemmy.world")
        #expect(await spy.metadataCallCount == 1)
        #expect(viewModel.metadata(forHost: "lemmy.world") == Self.knownMetadata)

        // A repeat open of the same host does not re-probe (idempotent per host).
        await viewModel.loadInstanceMetadata(forHost: "lemmy.world")
        #expect(await spy.metadataCallCount == 1)
    }

    @Test
    func nilMetadata_leavesNoChipState() async throws {
        let spy = SpyNodeInfoService(result: nil)
        let viewModel = try makeViewModel(spy: spy)
        try await waitUntilNotLoading(viewModel)

        await viewModel.loadInstanceMetadata(forHost: "lemmy.world")
        // Fail-open: the probe ran, but a nil result stores no metadata, so the
        // chips stay absent.
        #expect(await spy.metadataCallCount == 1)
        #expect(viewModel.metadata(forHost: "lemmy.world") == nil)
    }
}
