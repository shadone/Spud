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
/// The accessor coverage (Task 1) is joined here by the row-observation and
/// lazy-feed-gate coverage (Task 2): `startObservations()` owns the full
/// bring-up (feed-row gate -> lazy first-page fetch -> observe), storing the
/// ordered rows + the `serverPostId` lookup atomically per emit, bumping the
/// published `rowsRevision` signal, capturing the first snapshot's read ids,
/// and honouring the keeping / non-keeping restart flavors.
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
        /// The seeded site's local row id, reused as the `siteId` for the
        /// creator person the observation tests seed via ``seedFeedWithPosts``.
        let siteId: Int64
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

        let (accountId, siteId) = try await appDatabase.writer.write { db -> (Int64, Int64) in
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
            siteId: siteId,
            instanceActorId: instanceActorId
        )
    }

    private func makeViewModel(
        _ seed: Seed,
        feedKey: String = "feed-1",
        fetchFeedOperation: @escaping @MainActor (FeedHandle, String?) async throws -> String? = { _, _ in nil }
    ) -> PostListViewModel {
        PostListViewModel(
            feed: FeedHandle(
                feedKey: feedKey,
                feedType: .frontpage(listingType: .All, sortType: .Active)
            ),
            accountScope: seed.dependencies.accountService.scope(forAccountKeychainId: seed.keychainId),
            appDatabase: seed.appDatabase,
            dependencies: seed.dependencies,
            // The accessor tests default to a no-op fetch; the observation
            // tests inject one that persists a feed page (the lazy-feed gate).
            fetchFeedOperation: fetchFeedOperation
        )
    }

    // MARK: - Feed / post seeding (observation tests)

    /// Seeds a feed keyed by `feedKey` with one page and the given posts (each
    /// a real community/person/post/pageElement chain), so
    /// `observePostListRows` returns them in `position` order. The lazy-feed
    /// test calls this from inside the injected fetch to reproduce the
    /// importer creating the feed row on the first fetch. Returns the feed row
    /// id.
    @discardableResult
    private func seedFeedWithPosts(
        _ seed: Seed,
        feedKey: String,
        posts: [(serverPostId: Int64, title: String, isRead: Bool)]
    ) async throws -> Int64 {
        try await seed.appDatabase.writer.write { db -> Int64 in
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

            var feed = FeedRecord(
                accountId: seed.accountId,
                feedKey: feedKey,
                savedOnly: false,
                sortType: "Hot",
                createdAt: Date()
            )
            try feed.insert(db)

            var page = PageRecord(feedId: feed.id!, position: 0, createdAt: Date())
            try page.insert(db)

            for (index, spec) in posts.enumerated() {
                var post = PostRecord(
                    accountId: seed.accountId,
                    communityId: community.id!,
                    creatorId: creator.id!,
                    postId: spec.serverPostId,
                    title: spec.title,
                    originalPostUrl: "https://example.com/post/\(spec.serverPostId)",
                    isRead: spec.isRead,
                    published: Date(timeIntervalSince1970: 1_000_000 + Double(index))
                )
                try post.insert(db)

                var element = PageElementRecord(
                    pageId: page.id!,
                    postId: post.id!,
                    position: Int64(index)
                )
                try element.insert(db)
            }

            return feed.id!
        }
    }

    /// Bounded poll for an async-published condition. Returns as soon as the
    /// predicate holds, or after `timeout`. The GRDB row observation delivers
    /// off a global queue and hops back to the main actor, so a fixed
    /// `Task.yield()` does not always pump it in time.
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

    // MARK: - Row observation + revision signal

    @Test
    func startObservationsLandsSeededRowsInOrderAndBumpsRevision() async throws {
        let seed = try await makeSeed()
        try await seedFeedWithPosts(seed, feedKey: "feed-1", posts: [
            (serverPostId: 1001, title: "first", isRead: false),
            (serverPostId: 1002, title: "second", isRead: false),
            (serverPostId: 1003, title: "third", isRead: false),
        ])
        let vm = makeViewModel(seed)

        // Precondition: nothing emitted yet.
        #expect(vm.rowsRevision == 0)
        #expect(vm.orderedRows.isEmpty)

        vm.startObservations()
        await poll { vm.orderedRows.count == 3 }

        // A DB emit stores the rows then bumps the published signal.
        #expect(vm.rowsRevision >= 1, "a row emit must bump the revision signal")
        // Ordered by page.position, pageElement.position ASC.
        #expect(vm.orderedRows.map(\.serverPostId) == [1001, 1002, 1003])
        #expect(vm.orderedRows.map(\.title) == ["first", "second", "third"])

        vm.stopObservations()
    }

    @Test
    func rowLookupIsBuiltInTheSameTurnAsOrderedRows() async throws {
        // The serverPostId lookup lives on the view model and is rebuilt inside
        // `updateRows` in the same synchronous turn that stores the ordered
        // rows, so the two can never drift (the reason the lookup moved off the
        // view controller). Assert both together right after the emit lands.
        let seed = try await makeSeed()
        try await seedFeedWithPosts(seed, feedKey: "feed-1", posts: [
            (serverPostId: 1001, title: "first", isRead: false),
            (serverPostId: 1002, title: "second", isRead: false),
        ])
        let vm = makeViewModel(seed)

        // Precondition: no rows, no lookup before any emit.
        #expect(vm.orderedRows.isEmpty)
        #expect(vm.row(forServerPostId: 1001) == nil)

        vm.startObservations()
        await poll { vm.orderedRows.count == 2 }

        // Everything below is synchronous (no `await`), so no queued observation
        // can interleave between the rows and lookup assertions.
        #expect(vm.orderedRows.count == 2)
        for row in vm.orderedRows {
            #expect(vm.row(forServerPostId: row.serverPostId)?.serverPostId == row.serverPostId)
            #expect(vm.row(forServerPostId: row.serverPostId)?.title == row.title)
        }
        // An id not in the snapshot resolves to nil.
        #expect(vm.row(forServerPostId: 9999) == nil)

        vm.stopObservations()
    }

    @Test
    func firstSnapshotReadIdsCapturesReadPostsFromFirstEmit() async throws {
        // The pinned-read seed the view controller consumes must reflect exactly
        // the posts already read at the FIRST snapshot (see :1088). Seed a mix of
        // read / unread posts and assert the captured set is the read ids only.
        let seed = try await makeSeed()
        try await seedFeedWithPosts(seed, feedKey: "feed-1", posts: [
            (serverPostId: 1001, title: "read-a", isRead: true),
            (serverPostId: 1002, title: "unread", isRead: false),
            (serverPostId: 1003, title: "read-b", isRead: true),
        ])
        let vm = makeViewModel(seed)

        // Precondition: nothing captured before the first emit.
        #expect(vm.firstSnapshotReadIds.isEmpty)

        vm.startObservations()
        await poll { vm.orderedRows.count == 3 }

        #expect(vm.firstSnapshotReadIds == [1001, 1003])

        vm.stopObservations()
    }

    @Test
    func liveRowWriteMidObservationBumpsRevisionAgainAndAppears() async throws {
        let seed = try await makeSeed()
        try await seedFeedWithPosts(seed, feedKey: "feed-1", posts: [
            (serverPostId: 1001, title: "first", isRead: false),
            (serverPostId: 1002, title: "second", isRead: false),
        ])
        let vm = makeViewModel(seed)

        vm.startObservations()
        await poll { vm.orderedRows.count == 2 }
        let revisionAfterInitial = vm.rowsRevision
        #expect(revisionAfterInitial >= 1)
        // Nothing was read at the first emit; the pin captured that.
        let pinAfterFirstEmit = vm.firstSnapshotReadIds
        #expect(pinAfterFirstEmit.isEmpty)

        // Mark a post read while the observation is live: the row's isRead
        // change must re-fire the observation and bump the revision again.
        try await seed.appDatabase.writer.write { db in
            try db.execute(
                sql: "UPDATE post SET isRead = 1 WHERE postId = ?",
                arguments: [1001]
            )
        }

        await poll { vm.row(forServerPostId: 1001)?.isRead == true }
        #expect(vm.rowsRevision > revisionAfterInitial, "a live row change must bump the revision again")
        // The pin is a FIRST-snapshot capture: a later emit must never
        // re-capture it (posts read mid-session stay visible under `onRefresh`
        // hide-read until the next refresh). Guards the `isFirstSnapshot` gate.
        #expect(
            vm.firstSnapshotReadIds == pinAfterFirstEmit,
            "a later emit must not re-capture firstSnapshotReadIds"
        )

        vm.stopObservations()
    }

    // MARK: - Lazy-feed gate

    @Test
    func lazyFeedGateAwaitsFetchThenObservesRows() async throws {
        // No feed row exists for the view model's feed key: the bring-up must
        // await the injected first-page fetch (which persists the feed page,
        // reproducing the importer), then resolve the feed row id and observe
        // its rows. This is the zero-coverage lazy path.
        let seed = try await makeSeed()
        var fetchCount = 0
        let vm = makeViewModel(seed, feedKey: "feed-lazy", fetchFeedOperation: { [self] _, _ in
            fetchCount += 1
            _ = try await seedFeedWithPosts(seed, feedKey: "feed-lazy", posts: [
                (serverPostId: 2001, title: "lazy-a", isRead: false),
                (serverPostId: 2002, title: "lazy-b", isRead: false),
            ])
            return nil
        })

        // Precondition: the feed row does not exist yet.
        #expect(seed.appDatabase.feedRowIdSync(forFeedKey: "feed-lazy") == nil)

        vm.startObservations()
        await poll { vm.orderedRows.count == 2 }

        #expect(fetchCount == 1, "the gate must await the lazy first-page fetch exactly once")
        #expect(vm.orderedRows.map(\.serverPostId) == [2001, 2002])
        #expect(vm.rowsRevision >= 1)

        vm.stopObservations()
    }

    // MARK: - Restart flavors

    @Test
    func restartObservationsKeepingContentKeepsRowsUntilNewEmit() async throws {
        let seed = try await makeSeed()
        try await seedFeedWithPosts(seed, feedKey: "feed-1", posts: [
            (serverPostId: 1001, title: "first", isRead: false),
            (serverPostId: 1002, title: "second", isRead: false),
        ])
        let vm = makeViewModel(seed)

        vm.startObservations()
        await poll { vm.orderedRows.count == 2 }

        // A keeping restart leaves the rows + lookup in place (the refresh
        // control is the only progress indicator) until the new observation's
        // first emit swaps them in. Asserted synchronously right after the call,
        // before any new emit can land.
        vm.restartObservations(keepingContent: true)
        #expect(vm.orderedRows.count == 2, "keeping restart must not clear the rows")
        #expect(vm.row(forServerPostId: 1001) != nil, "keeping restart must not clear the lookup")

        vm.stopObservations()
    }

    @Test
    func restartObservationsNonKeepingResetsRowsAndLookup() async throws {
        let seed = try await makeSeed()
        try await seedFeedWithPosts(seed, feedKey: "feed-1", posts: [
            (serverPostId: 1001, title: "first", isRead: false),
            (serverPostId: 1002, title: "second", isRead: false),
        ])
        let vm = makeViewModel(seed)

        vm.startObservations()
        await poll { vm.orderedRows.count == 2 }

        // A non-keeping restart clears the rows + lookup synchronously so
        // nothing stale renders while the new feed loads. Asserted synchronously
        // right after the call, before any new emit can land.
        vm.restartObservations(keepingContent: false)
        #expect(vm.orderedRows.isEmpty, "non-keeping restart must clear the rows")
        #expect(vm.row(forServerPostId: 1001) == nil, "non-keeping restart must clear the lookup")

        vm.stopObservations()
    }
}
