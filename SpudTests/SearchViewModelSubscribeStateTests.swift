//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudDataKit
import Testing
@testable import Spud

/// Covers the root-cause fix for Search's stale/lossy community subscribe state
/// (see `docs/superpowers` fix report): `SearchViewModel.subscribeState(for:)`
/// must prefer the persisted, authoritative `CommunityRecord.subscribedState`
/// over the search response's transient, lossy `followState` — this is what
/// makes a community that requires moderator approval show "Pending" in Search
/// instead of a false "Subscribed", and keeps a re-search from reverting an
/// already-pending row back to "Subscribe".
@MainActor
struct SearchViewModelSubscribeStateTests {
    /// Seeds the minimal account graph (instance -> site -> account) and returns
    /// the account row id, mirroring `FavoritedCommunityQueriesTests`.
    @discardableResult
    private func seedAccount(_ appDatabase: AppDatabase, keychainId: String) async throws -> Int64 {
        try await appDatabase.writer.write { db in
            try db.execute(sql: "INSERT INTO instance (actorId, createdAt) VALUES (?, ?)", arguments: ["https://\(keychainId).test", Date()])
            let instanceId = db.lastInsertedRowID
            try db.execute(sql: "INSERT INTO site (instanceId, createdAt, updatedAt) VALUES (?, ?, ?)", arguments: [instanceId, Date(), Date()])
            let siteId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO account (siteId, accountKeychainId, isDefault, isServiceAccount, isSignedOutAccountType, createdAt, updatedAt)
                VALUES (?, ?, 0, 0, 0, ?, ?)
                """, arguments: [siteId, keychainId, Date(), Date()])
            return db.lastInsertedRowID
        }
    }

    /// Inserts a followed `CommunityRecord` (`subscribedState`, plus the
    /// `accountFollowedCommunity` junction row `observeFollowedCommunities` reads)
    /// for `accountId`, keyed by `actorId`.
    private func seedFollowedCommunity(
        _ appDatabase: AppDatabase,
        accountId: Int64,
        communityId: Int64,
        actorId: String,
        subscribedState: CommunitySubscribedState
    ) async throws {
        try await appDatabase.writer.write { db in
            var community = CommunityRecord(
                accountId: accountId,
                communityId: communityId,
                name: "tincidunt",
                actorId: actorId,
                subscribedState: subscribedState.rawValue
            )
            try community.insert(db)
            let followed = AccountFollowedCommunityRecord(accountId: accountId, communityId: community.id!)
            try followed.insert(db)
        }
    }

    private func makeViewModel(
        appDatabase: AppDatabase,
        accountKeychainId: String
    ) -> SearchViewModel {
        let accountService = AccountService(appDatabase: appDatabase)
        return SearchViewModel(
            accountScope: accountService.scope(forAccountKeychainId: accountKeychainId),
            alertService: AlertService(),
            preferencesService: PreferencesService.ephemeral(),
            appDatabase: appDatabase,
            isKnownInstance: { _ in false },
            searchInstances: { _ in [] }
        )
    }

    /// Waits until `subscribeStates` has been populated by the live
    /// `observeFollowedCommunities` observation (its first yield lands
    /// asynchronously), or gives up after a couple of seconds.
    private func waitUntilPopulated(_ viewModel: SearchViewModel) async {
        let deadline = Date().addingTimeInterval(2)
        while viewModel.subscribeStates.isEmpty {
            if Date() > deadline { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    @Test
    func persistedPendingState_winsOverStaleNetworkFollowState() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let accountId = try await seedAccount(appDatabase, keychainId: "kc-pending")
        let communityUrl = "https://lemmy.world/c/tincidunt"
        try await seedFollowedCommunity(
            appDatabase,
            accountId: accountId,
            communityId: 42,
            actorId: communityUrl,
            subscribedState: .pending
        )

        let viewModel = makeViewModel(appDatabase: appDatabase, accountKeychainId: "kc-pending")
        await waitUntilPopulated(viewModel)

        // The search response's own `followState` is stale/lossy here (a v3
        // response never reports "approval required" — it's `.notFollowing` or
        // `.pending`); either way the persisted `.pending` must win.
        let result = SearchCommunityResult.fixture(followState: .notFollowing, communityUrl: communityUrl)
        #expect(viewModel.subscribeState(for: result) == .pending)
    }

    @Test
    func communityAbsentFromDatabase_fallsBackToNetworkFollowState() async throws {
        let appDatabase = try AppDatabase.inMemory()
        // No community seeded at all for this account.
        try await seedAccount(appDatabase, keychainId: "kc-empty")

        let viewModel = makeViewModel(appDatabase: appDatabase, accountKeychainId: "kc-empty")
        // Nothing to observe, so there's no async population to wait for; assert
        // directly that the map stays empty and the fallback kicks in.
        #expect(viewModel.subscribeStates.isEmpty)

        let result = SearchCommunityResult.fixture(
            followState: .accepted,
            communityUrl: "https://lemmy.world/c/never-seen"
        )
        #expect(viewModel.subscribeState(for: result) == .subscribed)
    }

    @Test
    func signedOutAccount_neverObserves_alwaysFallsBackToNetworkState() throws {
        let appDatabase = try AppDatabase.inMemory()
        let viewModel = makeViewModel(appDatabase: appDatabase, accountKeychainId: "kc-never-registered")
        #expect(viewModel.accountScope.isSignedOut)

        let result = SearchCommunityResult.fixture(followState: .pending, communityUrl: "https://lemmy.world/c/x")
        #expect(viewModel.subscribeState(for: result) == .pending)
    }
}
