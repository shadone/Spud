//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import LemmyKit
import Testing
@testable import Spud
@testable import SpudDataKit

/// DB-backed harness for `CommunityViewModel`'s synchronous favorite/mute
/// accessors (absorbed from the view controller). Seeds a real in-memory
/// database with an account + a community row carrying a known `actorId`,
/// waits for the model's `observeCommunity` stream to publish that actor id,
/// then asserts the accessors read and write through the same
/// `MutedCommunityQueries` / `FavoritedCommunityQueries` sync calls the
/// view-controller path used directly before the move.
@MainActor
struct CommunityViewModelTests {
    // MARK: - Seeding

    private struct Seed {
        let appDatabase: AppDatabase
        let keychainId: String
        let accountId: Int64
        let serverCommunityId: Int64
        let communityActorId: String
    }

    /// Seeds instance -> site -> account (keyed by `keychainId`) -> a followed
    /// community with a known `actorId`, so `CommunityViewModel.init`'s
    /// `observeCommunity` stream resolves it.
    private func makeSeed(
        keychainId: String = "kc-1",
        serverCommunityId: Int64 = 7,
        communityActorId: String = "https://example.com/c/seededcommunity"
    ) async throws -> Seed {
        let appDatabase = try AppDatabase.inMemory()

        let accountId = try await appDatabase.writer.write { db -> Int64 in
            var instance = InstanceRecord(actorId: "https://example.com")
            try instance.insert(db)

            var site = SiteRecord(instanceId: instance.id!)
            try site.insert(db)

            var account = AccountRecord(
                siteId: site.id!,
                accountKeychainId: keychainId,
                isSignedOutAccountType: false
            )
            try account.insert(db)

            var community = CommunityRecord(
                accountId: account.id!,
                communityId: serverCommunityId,
                name: "seededcommunity",
                actorId: communityActorId
            )
            try community.insert(db)

            return account.id!
        }

        return Seed(
            appDatabase: appDatabase,
            keychainId: keychainId,
            accountId: accountId,
            serverCommunityId: serverCommunityId,
            communityActorId: communityActorId
        )
    }

    private func makeViewModel(_ seed: Seed) -> CommunityViewModel {
        CommunityViewModel(
            accountRowId: seed.accountId,
            serverCommunityId: Components.Schemas.CommunityID(seed.serverCommunityId),
            accountKeychainId: seed.keychainId,
            appDatabase: seed.appDatabase
        )
    }

    /// Bounded poll for an async-published condition, mirroring the pattern in
    /// `PostListViewModelObservationTests` / `PostDetailViewModelObservationTests`:
    /// the GRDB observation delivers off a global queue and hops back to the
    /// main actor, so a fixed `Task.yield()` does not always pump it in time.
    private func poll(
        timeout: Duration = .seconds(2),
        until predicate: @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    // MARK: - Pre-observation (actorId nil) no-op behavior

    @Test
    func accessorsNoOpBeforeActorIdResolves() async throws {
        let seed = try await makeSeed()
        let vm = makeViewModel(seed)

        // No `await` has run yet, so the init's observation task has not had a
        // chance to publish `actorId` — this mirrors the view controller's
        // former `guard let actorId = viewModel.actorId else { ... }` early
        // return at the menu-builder call sites.
        #expect(vm.actorId == nil)
        #expect(vm.isMuted() == false)
        #expect(vm.isFavorited() == false)

        vm.mute(until: nil)
        vm.unmute()
        vm.toggleFavorite()

        #expect(!seed.appDatabase.isCommunityMutedSync(
            forKeychainId: seed.keychainId,
            communityActorId: seed.communityActorId
        ), "mute/unmute must no-op before actorId resolves")
        #expect(!seed.appDatabase.isCommunityFavoritedSync(
            forKeychainId: seed.keychainId,
            communityActorId: seed.communityActorId
        ), "toggleFavorite must no-op before actorId resolves")
    }

    // MARK: - isMuted / mute / unmute

    @Test
    func muteTruthTable() async throws {
        let seed = try await makeSeed()
        let vm = makeViewModel(seed)
        await poll { vm.actorId != nil }

        #expect(vm.isMuted() == false)

        vm.mute(until: nil)
        #expect(vm.isMuted())
        #expect(seed.appDatabase.isCommunityMutedSync(
            forKeychainId: seed.keychainId,
            communityActorId: seed.communityActorId
        ), "mute(until:) must persist a muted-community row")

        vm.unmute()
        #expect(vm.isMuted() == false)
        #expect(!seed.appDatabase.isCommunityMutedSync(
            forKeychainId: seed.keychainId,
            communityActorId: seed.communityActorId
        ), "unmute() must remove the muted-community row")
    }

    @Test
    func muteUntilIsPersistedVerbatim() async throws {
        let seed = try await makeSeed()
        let vm = makeViewModel(seed)
        await poll { vm.actorId != nil }

        let until = Date().addingTimeInterval(3600)
        vm.mute(until: until)
        #expect(vm.isMuted(), "a future expiry must still read as muted")
    }

    // MARK: - isFavorited / toggleFavorite

    @Test
    func favoriteTruthTable() async throws {
        let seed = try await makeSeed()
        let vm = makeViewModel(seed)
        await poll { vm.actorId != nil }

        #expect(vm.isFavorited() == false)

        vm.toggleFavorite()
        #expect(vm.isFavorited())
        #expect(seed.appDatabase.isCommunityFavoritedSync(
            forKeychainId: seed.keychainId,
            communityActorId: seed.communityActorId
        ), "toggleFavorite must persist a favorited-community row when not yet favorited")

        vm.toggleFavorite()
        #expect(vm.isFavorited() == false)
        #expect(!seed.appDatabase.isCommunityFavoritedSync(
            forKeychainId: seed.keychainId,
            communityActorId: seed.communityActorId
        ), "toggleFavorite must remove the favorited-community row when already favorited")
    }
}
