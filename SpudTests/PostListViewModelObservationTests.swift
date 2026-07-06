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

/// DB-backed harness for `PostListViewModel`'s synchronous data accessors. Seeds
/// a real in-memory database with the minimal rows the accessors resolve
/// against (instance / site / account keyed by keychain id), then asserts the
/// view model reads and writes through the same accessors the production
/// (view controller) path uses.
///
/// This file starts with the accessor coverage (Task 1); the row-observation
/// and lazy-feed-gate tests land alongside that move in Task 2.
@MainActor
struct PostListViewModelObservationTests {
    // MARK: - Dependencies

    private struct TestDependencies:
        HasAccountService, HasPreferencesService, HasReachabilityMonitor
    {
        let appDatabase: AppDatabase
        let accountService: AccountServiceType
        let preferencesService: PreferencesServiceType
        let reachabilityMonitor: ReachabilityMonitoring
    }

    /// Everything a test needs to build the view model and assert against the DB.
    private struct Seed {
        let appDatabase: AppDatabase
        let dependencies: TestDependencies
        let keychainId: String
        let accountId: Int64
        /// The seeded home-instance actor id, i.e. what `instanceActorId` must
        /// resolve to for this account.
        let instanceActorId: String
    }

    // MARK: - Seeding

    /// Seeds instance -> site -> account (keyed by `keychainId`) in an in-memory
    /// database and returns the ids + the constructed dependencies.
    private func makeSeed(
        keychainId: String = "kc-1",
        instanceActorId: String = "https://example.com"
    ) async throws -> Seed {
        let appDatabase = try AppDatabase.inMemory()

        let accountId = try await appDatabase.writer.write { db -> Int64 in
            var instance = InstanceRecord(actorId: instanceActorId)
            try instance.insert(db)

            var site = SiteRecord(instanceId: instance.id!)
            try site.insert(db)

            var account = AccountRecord(
                siteId: site.id!,
                accountKeychainId: keychainId,
                isSignedOutAccountType: false
            )
            try account.insert(db)

            return account.id!
        }

        let dependencies = TestDependencies(
            appDatabase: appDatabase,
            accountService: AccountService(appDatabase: appDatabase),
            preferencesService: PreferencesService(),
            reachabilityMonitor: StaticReachabilityMonitor(isOnline: true)
        )

        return Seed(
            appDatabase: appDatabase,
            dependencies: dependencies,
            keychainId: keychainId,
            accountId: accountId,
            instanceActorId: instanceActorId
        )
    }

    private func makeViewModel(_ seed: Seed) -> PostListViewModel {
        PostListViewModel(
            feed: FeedHandle(
                feedKey: "feed-1",
                feedType: .frontpage(listingType: .All, sortType: .Active)
            ),
            accountScope: seed.dependencies.accountService.scope(forAccountKeychainId: seed.keychainId),
            appDatabase: seed.appDatabase,
            dependencies: seed.dependencies,
            // Neutralize the network feed fetch; these tests exercise the
            // synchronous accessors only.
            fetchFeedOperation: { _, _ in nil }
        )
    }

    // MARK: - instanceActorId accessor

    @Test
    func instanceActorIdResolvesSeededAccount() async throws {
        let seed = try await makeSeed(instanceActorId: "https://lemmy.example")
        let vm = makeViewModel(seed)

        #expect(vm.instanceActorId == "https://lemmy.example")
    }

    @Test
    func instanceActorIdIsNilForUnknownAccount() async throws {
        // A view model whose keychain id has no imported account row: the
        // instance join can't resolve, so the accessor is nil.
        let seed = try await makeSeed(keychainId: "kc-1")
        let vm = PostListViewModel(
            feed: FeedHandle(
                feedKey: "feed-1",
                feedType: .frontpage(listingType: .All, sortType: .Active)
            ),
            accountScope: seed.dependencies.accountService.scope(forAccountKeychainId: "kc-unknown"),
            appDatabase: seed.appDatabase,
            dependencies: seed.dependencies,
            fetchFeedOperation: { _, _ in nil }
        )

        #expect(vm.instanceActorId == nil)
    }

    // MARK: - accountAndSiteRowIds accessor

    @Test
    func accountAndSiteRowIdsResolvesSeededAccount() async throws {
        let seed = try await makeSeed()
        let vm = makeViewModel(seed)

        let ids = try #require(vm.accountAndSiteRowIds())
        #expect(ids.accountId == seed.accountId)
    }

    // MARK: - muteCommunity accessor

    @Test
    func muteCommunityWritesTheMuteRow() async throws {
        let seed = try await makeSeed()
        let vm = makeViewModel(seed)

        let communityActorId = "https://example.com/c/seededcommunity"
        #expect(!seed.appDatabase.isCommunityMutedSync(
            forKeychainId: seed.keychainId,
            communityActorId: communityActorId
        ))

        vm.muteCommunity(communityActorId: communityActorId, until: nil)

        #expect(seed.appDatabase.isCommunityMutedSync(
            forKeychainId: seed.keychainId,
            communityActorId: communityActorId
        ), "muteCommunity must persist a muted-community row")
    }

    // MARK: - recordSeen accessor

    @Test
    func recordSeenPersistsTheInteraction() async throws {
        let seed = try await makeSeed()
        let vm = makeViewModel(seed)
        let serverPostId: Int64 = 4242

        // Precondition: no interaction row yet.
        let before = try await seed.appDatabase.writer.read { db in
            try PostInteractionRecord
                .filter(Column("accountId") == seed.accountId)
                .filter(Column("postServerId") == serverPostId)
                .fetchOne(db)
        }
        #expect(before == nil)

        let snapshot = PostInteractionSnapshot(
            titleSnapshot: "Seen title",
            communityName: "seencommunity",
            instanceHost: "example.com",
            thumbnailUrl: nil,
            author: "seenauthor"
        )
        await vm.recordSeen(serverPostId: serverPostId, snapshot: snapshot)

        let record = try await seed.appDatabase.writer.read { db in
            try PostInteractionRecord
                .filter(Column("accountId") == seed.accountId)
                .filter(Column("postServerId") == serverPostId)
                .fetchOne(db)
        }
        let seen = try #require(record, "recordSeen must persist an interaction row")
        #expect(seen.lastSeenAt != nil)
        #expect(seen.seenCount == 1)
        #expect(seen.titleSnapshot == "Seen title")
    }
}
