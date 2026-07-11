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

/// Covers `PostListViewModel` driving the local-only Downloaded feed: it observes
/// the durable `post.downloadedAt` rows (newest download first) and NEVER touches
/// the network — the single most important invariant of this feature.
@MainActor
struct PostListViewModelDownloadedFeedTests {
    private struct TestDependencies:
        HasAccountService, HasPreferencesService, HasReachabilityMonitor
    {
        let appDatabase: AppDatabase
        let accountService: AccountServiceType
        let preferencesService: PreferencesServiceType
        let reachabilityMonitor: ReachabilityMonitoring
    }

    private struct Seed {
        let appDatabase: AppDatabase
        let dependencies: TestDependencies
        let keychainId: String
        let accountId: Int64
        let siteId: Int64
    }

    private func makeSeed(keychainId: String = "kc-1") async throws -> Seed {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId) = try await appDatabase.writer.write { db -> (Int64, Int64) in
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
            return (account.id!, site.id!)
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
            siteId: siteId
        )
    }

    /// Seeds posts marked for offline reading. Index 0 is the OLDEST download, so
    /// `downloadedAt DESC` sorts the last element first. NO feed / page /
    /// pageElement rows — the Downloaded feed reads straight from
    /// `post.downloadedAt`, proving it works after the ephemeral feed is GC'd.
    private func seedDownloadedPosts(
        _ seed: Seed,
        posts: [(serverPostId: Int64, title: String)]
    ) async throws {
        try await seed.appDatabase.writer.write { db in
            var community = CommunityRecord(
                accountId: seed.accountId,
                communityId: 7,
                name: "seededcommunity"
            )
            try community.insert(db)

            var creator = PersonRecord(
                siteId: seed.siteId,
                personId: 99,
                name: "seededcreator",
                actorId: "https://example.com/u/seededcreator"
            )
            try creator.insert(db)

            for (index, spec) in posts.enumerated() {
                var post = PostRecord(
                    accountId: seed.accountId,
                    communityId: community.id!,
                    creatorId: creator.id!,
                    postId: spec.serverPostId,
                    title: spec.title,
                    originalPostUrl: "https://example.com/post/\(spec.serverPostId)",
                    downloadedAt: Date(timeIntervalSince1970: 1_000_000 + Double(index)),
                    published: Date(timeIntervalSince1970: 500_000 + Double(index))
                )
                try post.insert(db)
            }
        }
    }

    private func makeViewModel(
        _ seed: Seed,
        fetchFeedOperation: @escaping @MainActor (FeedHandle, String?) async throws -> String?
    ) -> PostListViewModel {
        PostListViewModel(
            feed: FeedHandle(
                feedKey: "dl-feed",
                feedType: .downloaded(sortType: .New)
            ),
            accountScope: seed.dependencies.accountService.scope(forAccountKeychainId: seed.keychainId),
            appDatabase: seed.appDatabase,
            dependencies: seed.dependencies,
            fetchFeedOperation: fetchFeedOperation
        )
    }

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

    // MARK: - Title

    @Test
    func navigationTitleIsDownloaded() async throws {
        let seed = try await makeSeed()
        let vm = makeViewModel(seed) { _, _ in nil }
        #expect(vm.navigationTitle == "Downloaded")
    }

    // MARK: - Observation

    @Test
    func startObservationsLandsDownloadedRowsNewestDownloadFirst() async throws {
        let seed = try await makeSeed()
        try await seedDownloadedPosts(seed, posts: [
            (serverPostId: 1001, title: "older download"),
            (serverPostId: 1002, title: "middle download"),
            (serverPostId: 1003, title: "newest download"),
        ])
        let vm = makeViewModel(seed) { _, _ in nil }

        vm.startObservations()
        await poll { vm.orderedRows.count == 3 }

        // downloadedAt DESC: last seeded (index 2) is newest, so it sorts first.
        #expect(vm.orderedRows.map(\.serverPostId) == [1003, 1002, 1001])
        #expect(vm.loadState == .loaded)

        vm.stopObservations()
    }

    @Test
    func emptyDownloadedFeedSettlesToEmptyNotStuckLoading() async throws {
        let seed = try await makeSeed()
        let vm = makeViewModel(seed) { _, _ in nil }

        vm.startObservations()
        // No downloaded posts: the observation must settle to `.empty` (not spin
        // the skeleton forever), because the Downloaded feed marks its initial
        // fetch complete up front.
        await poll { vm.loadState == .empty }
        #expect(vm.loadState == .empty)
        #expect(vm.orderedRows.isEmpty)

        vm.stopObservations()
    }

    // MARK: - Network-free invariant (the single most important check)

    @Test
    func downloadedFeedNeverCallsTheNetwork() async throws {
        let seed = try await makeSeed()
        try await seedDownloadedPosts(seed, posts: [
            (serverPostId: 1001, title: "downloaded"),
        ])

        // fetchFeedOperation is the view model's ONLY network path (it wraps
        // scope.lemmyService.fetchFeed). Any invocation fails the test — the
        // Downloaded feed must be entirely local.
        var fetchInvocations = 0
        let vm = makeViewModel(seed) { _, _ in
            fetchInvocations += 1
            Issue.record("Downloaded feed must never call fetchFeed")
            return nil
        }

        // Bring-up + every user-driven refresh / pagination path.
        vm.startObservations()
        await poll { vm.orderedRows.count == 1 }
        await vm.loadFirstPage()
        await vm.loadMore()
        vm.didClickReload()
        vm.didScrollToBottom()
        await vm.retryPagination()
        // Give any errantly-spawned fetch task a chance to run before asserting.
        try? await Task.sleep(for: .milliseconds(50))

        #expect(fetchInvocations == 0, "the Downloaded feed issued a network request")
        // The posts are still there and the load is settled (never a spinner).
        #expect(vm.orderedRows.map(\.serverPostId) == [1001])
        #expect(vm.loadState == .loaded)

        vm.stopObservations()
    }
}
