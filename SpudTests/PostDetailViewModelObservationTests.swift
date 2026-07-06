//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import LemmyKit
import SpudDataKit
import Testing
@testable import Spud

/// DB-backed harness for `PostDetailViewModel`'s data observations. Seeds a real
/// in-memory database with the minimal rows the header + comments observations
/// and visit recording need (instance / site / account / community / creator /
/// post / comment tree), then asserts the view model publishes `headerRow`,
/// drives the comment tree into `orderedComments` while bumping the
/// `commentsRevision` signal once per DB emit, and records the visit through the
/// same synchronous read accessors the production path uses.
///
/// The GRDB observation delivers off a global queue and hops back to the main
/// actor, so the published state is awaited with a bounded poll (no wall-clock
/// dependency on a fixed sleep — it returns as soon as the predicate holds).
@MainActor
struct PostDetailViewModelObservationTests {
    // MARK: - Dependencies

    private struct TestDependencies:
        HasAccountService, HasAlertService, HasPreferencesService, HasReachabilityMonitor
    {
        let accountService: AccountServiceType
        let alertService: AlertServiceType
        let preferencesService: PreferencesServiceType
        let reachabilityMonitor: ReachabilityMonitoring
    }

    /// Everything a test needs to build the view model and assert against the DB.
    private struct Seed {
        let appDatabase: AppDatabase
        let dependencies: TestDependencies
        let keychainId: String
        let serverPostId: Int64
        let postRowId: Int64
        let accountId: Int64
        /// The seeded creator person's local row id, reused as the `creatorId`
        /// for comments written by ``seedComments(_:sortType:specs:)``.
        let creatorRowId: Int64
        let title: String
        let body: String?
    }

    /// One comment to seed (a real `comment` + `commentElement` pair).
    private struct CommentSpec {
        let localId: Int64
        let position: Int64
        let depth: Int64
        let body: String
    }

    // MARK: - Seeding

    /// Seeds instance -> site -> account (keyed by `keychainId`) -> community +
    /// creator person -> post, plus an optional pre-existing interaction row with
    /// a known `lastOpenedAt`. Returns the ids + the constructed dependencies.
    private func makeSeed(
        keychainId: String = "kc-1",
        serverPostId: Int64 = 42,
        title: String = "Seeded post title",
        body: String? = "Seeded post body",
        preOpenedAt: Date? = nil
    ) async throws -> Seed {
        let appDatabase = try AppDatabase.inMemory()

        let (accountId, postRowId, creatorRowId) = try await appDatabase.writer.write { db -> (Int64, Int64, Int64) in
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
                communityId: 7,
                name: "seededcommunity"
            )
            try community.insert(db)

            var creator = PersonRecord(
                siteId: site.id!,
                personId: 99,
                name: "seededcreator",
                actorId: "https://example.com/u/seededcreator"
            )
            try creator.insert(db)

            var post = PostRecord(
                accountId: account.id!,
                communityId: community.id!,
                creatorId: creator.id!,
                postId: serverPostId,
                title: title,
                body: body,
                originalPostUrl: "https://example.com/post/\(serverPostId)",
                published: Date(timeIntervalSince1970: 1_000_000)
            )
            try post.insert(db)

            if let preOpenedAt {
                var interaction = PostInteractionRecord(
                    accountId: account.id!,
                    postServerId: serverPostId,
                    lastOpenedAt: preOpenedAt,
                    openedCount: 1
                )
                try interaction.insert(db)
            }

            return (account.id!, post.id!, creator.id!)
        }

        let dependencies = TestDependencies(
            accountService: AccountService(appDatabase: appDatabase),
            alertService: AlertService(),
            preferencesService: PreferencesService(),
            reachabilityMonitor: StaticReachabilityMonitor(isOnline: true)
        )

        return Seed(
            appDatabase: appDatabase,
            dependencies: dependencies,
            keychainId: keychainId,
            serverPostId: serverPostId,
            postRowId: postRowId,
            accountId: accountId,
            creatorRowId: creatorRowId,
            title: title,
            body: body
        )
    }

    /// Writes each spec as a real `comment` + `commentElement` pair for the
    /// seeded post, under `sortType` so the comments observation picks them up.
    /// Can run before or after ``PostDetailViewModel/startObservations()`` — a
    /// live write re-fires the observation. Returns the created element ids in
    /// the order given.
    @discardableResult
    private func seedComments(
        _ seed: Seed,
        sortType: String,
        specs: [CommentSpec]
    ) async throws -> [Int64] {
        try await seed.appDatabase.writer.write { db -> [Int64] in
            var elementIds: [Int64] = []
            for spec in specs {
                var comment = CommentRecord(
                    postId: seed.postRowId,
                    creatorId: seed.creatorRowId,
                    localCommentId: spec.localId,
                    body: spec.body,
                    published: Date(timeIntervalSince1970: 2_000_000 + Double(spec.position))
                )
                try comment.insert(db)

                var element = CommentElementRecord(
                    postId: seed.postRowId,
                    commentId: comment.id!,
                    position: spec.position,
                    depth: spec.depth,
                    sortType: sortType
                )
                try element.insert(db)
                elementIds.append(element.id!)
            }
            return elementIds
        }
    }

    private func makeViewModel(_ seed: Seed) -> PostDetailViewModel {
        PostDetailViewModel(
            serverPostId: Components.Schemas.PostID(seed.serverPostId),
            accountScope: seed.dependencies.accountService.scope(forAccountKeychainId: seed.keychainId),
            appDatabase: seed.appDatabase,
            dependencies: seed.dependencies,
            // Neutralize the network comment fetch the observation bring-up
            // kicks; these tests exercise the header observation + visit
            // recording only.
            fetchCommentsOperation: { _ in }
        )
    }

    /// Bounded poll for an async-published condition. Returns as soon as the
    /// predicate holds, or after `timeout`. Uses a short `Task.sleep` (not a
    /// fixed wall-clock wait) because the header observation hops from a global
    /// queue back to the main actor, which a bare `Task.yield()` does not always
    /// pump in time.
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

    // MARK: - Header observation

    @Test
    func startObservationsPublishesSeededHeaderRow() async throws {
        let seed = try await makeSeed()
        let vm = makeViewModel(seed)

        // Precondition: nothing observed yet.
        #expect(vm.headerRow == nil)

        vm.startObservations()

        // The row id resolves synchronously during bring-up.
        #expect(vm.postRowId == seed.postRowId)

        await poll { vm.headerRow != nil }

        let row = try #require(vm.headerRow)
        #expect(row.title == seed.title)
        #expect(row.body == seed.body)
        #expect(row.id == seed.postRowId)

        vm.stopObservations()
    }

    @Test
    func startObservationsLeavesHeaderRowNilAndFiresFetchWhenPostNotMirrored() async throws {
        // A view model pointed at a post that was never mirrored: the row id
        // cannot resolve, so no header observation starts and `postRowId` stays
        // nil (the bring-up instead kicks a comment fetch that dual-writes it).
        let seed = try await makeSeed()
        var fetchCount = 0
        let vm = PostDetailViewModel(
            serverPostId: Components.Schemas.PostID(seed.serverPostId + 1), // unmirrored id
            accountScope: seed.dependencies.accountService.scope(forAccountKeychainId: seed.keychainId),
            appDatabase: seed.appDatabase,
            dependencies: seed.dependencies,
            fetchCommentsOperation: { _ in fetchCount += 1 }
        )

        vm.startObservations()

        #expect(vm.postRowId == nil)
        // `didPrepareObservation` schedules the fetch on a Task; let it run.
        await poll { fetchCount > 0 }
        #expect(fetchCount == 1)
        #expect(vm.headerRow == nil)

        vm.stopObservations()
    }

    // MARK: - Visit recording

    @Test
    func recordVisitSeedsPreviousVisitFromPriorLastOpenedAt() async throws {
        // A prior visit's `lastOpenedAt` is pre-seeded; bring-up must read it into
        // `previousVisitAt` synchronously *before* the async open write overwrites
        // it, so the new-comment delta sees the correct reference point.
        let priorVisit = Date(timeIntervalSince1970: 1_500_000)
        let seed = try await makeSeed(preOpenedAt: priorVisit)
        let vm = makeViewModel(seed)

        vm.startObservations()

        // `recordVisit` runs synchronously inside `startObservations`.
        #expect(vm.previousVisitAt == priorVisit)

        vm.stopObservations()
    }

    @Test
    func recordVisitUpdatesInteractionRowAfterStart() async throws {
        // After bring-up, the fire-and-forget `recordPostOpened` write must land:
        // the interaction row's `lastOpenedAt` advances past the pre-seeded prior
        // visit (asserted via the same sync read the view model uses).
        let priorVisit = Date(timeIntervalSince1970: 1_500_000)
        let seed = try await makeSeed(preOpenedAt: priorVisit)
        let vm = makeViewModel(seed)

        vm.startObservations()

        await poll {
            let current = seed.appDatabase.lastOpenedAtSync(
                forKeychainId: seed.keychainId,
                serverPostId: seed.serverPostId
            )
            return current.map { $0 > priorVisit } ?? false
        }

        let updated = seed.appDatabase.lastOpenedAtSync(
            forKeychainId: seed.keychainId,
            serverPostId: seed.serverPostId
        )
        #expect(updated != nil)
        #expect((updated ?? priorVisit) > priorVisit, "recordPostOpened must advance lastOpenedAt")

        vm.stopObservations()
    }

    @Test
    func recordVisitCreatesInteractionRowOnFirstVisit() async throws {
        // No prior interaction row: bring-up creates one (first-ever open), so a
        // subsequent sync read returns a non-nil lastOpenedAt.
        let seed = try await makeSeed()
        let vm = makeViewModel(seed)

        #expect(seed.appDatabase.lastOpenedAtSync(
            forKeychainId: seed.keychainId,
            serverPostId: seed.serverPostId
        ) == nil)
        // First visit has no prior reference.
        vm.startObservations()
        #expect(vm.previousVisitAt == nil)

        await poll {
            seed.appDatabase.lastOpenedAtSync(
                forKeychainId: seed.keychainId,
                serverPostId: seed.serverPostId
            ) != nil
        }
        #expect(seed.appDatabase.lastOpenedAtSync(
            forKeychainId: seed.keychainId,
            serverPostId: seed.serverPostId
        ) != nil)

        vm.stopObservations()
    }

    // MARK: - Comments observation + revision signal

    @Test
    func startObservationsPublishesSeededCommentTreeInOrderAndBumpsRevision() async throws {
        let seed = try await makeSeed()
        let vm = makeViewModel(seed)
        let sortType = vm.commentSortType.rawValue

        // Precondition: nothing emitted yet — the revision starts at 0 and the
        // ordered tree is empty.
        #expect(vm.commentsRevision == 0)
        #expect(vm.orderedComments.isEmpty)

        try await seedComments(seed, sortType: sortType, specs: [
            CommentSpec(localId: 101, position: 0, depth: 1, body: "first"),
            CommentSpec(localId: 102, position: 1, depth: 1, body: "second"),
            CommentSpec(localId: 103, position: 2, depth: 1, body: "third"),
        ])

        vm.startObservations()

        await poll { vm.orderedComments.count == 3 }

        // A DB emit runs `updateOrderedComments` then bumps the published signal.
        #expect(vm.commentsRevision >= 1, "a comment emit must bump the revision signal")
        // Ordered by `commentElement.position ASC`.
        #expect(vm.orderedComments.map(\.serverCommentId) == [101, 102, 103])
        #expect(vm.orderedComments.map(\.position) == [0, 1, 2])
        #expect(vm.orderedComments.map(\.body) == ["first", "second", "third"])

        vm.stopObservations()
    }

    @Test
    func newCommentWrittenMidObservationBumpsRevisionAgainAndAppears() async throws {
        let seed = try await makeSeed()
        let vm = makeViewModel(seed)
        let sortType = vm.commentSortType.rawValue

        try await seedComments(seed, sortType: sortType, specs: [
            CommentSpec(localId: 101, position: 0, depth: 1, body: "first"),
            CommentSpec(localId: 102, position: 1, depth: 1, body: "second"),
        ])

        vm.startObservations()
        await poll { vm.orderedComments.count == 2 }

        let revisionAfterInitial = vm.commentsRevision
        #expect(revisionAfterInitial >= 1)

        // Write a new comment while the observation is live: it must re-fire,
        // bump the revision past the initial value, and appear in order.
        try await seedComments(seed, sortType: sortType, specs: [
            CommentSpec(localId: 103, position: 2, depth: 1, body: "third-live"),
        ])

        await poll { vm.orderedComments.count == 3 }

        #expect(vm.commentsRevision > revisionAfterInitial, "a live insert must bump the revision again")
        #expect(vm.orderedComments.map(\.serverCommentId) == [101, 102, 103])
        #expect(vm.orderedComments.last?.body == "third-live")

        vm.stopObservations()
    }

    @Test
    func collapseToggleDoesNotBumpRevision() async throws {
        let seed = try await makeSeed()
        let vm = makeViewModel(seed)
        let sortType = vm.commentSortType.rawValue

        try await seedComments(seed, sortType: sortType, specs: [
            CommentSpec(localId: 101, position: 0, depth: 1, body: "parent"),
            CommentSpec(localId: 102, position: 1, depth: 2, body: "child"),
        ])

        vm.startObservations()
        await poll { vm.orderedComments.count == 2 }

        // Snapshot the revision immediately after the emit. Everything below is
        // synchronous (no `await`), so no queued observation can interleave and
        // move the counter between capture and the assertions.
        let revisionAfterEmit = vm.commentsRevision
        #expect(revisionAfterEmit >= 1)

        let parentElementId = try #require(vm.orderedComments.first?.id)

        // Collapse is pure @ObservationIgnored view-layer state — it must NOT
        // bump the DB-emit revision (that is the whole reason the revision
        // exists as a separate signal from `orderedComments`).
        let collapsed = vm.toggleCollapse(elementId: parentElementId)
        #expect(collapsed)
        #expect(vm.isCollapsed(elementId: parentElementId))
        #expect(vm.commentsRevision == revisionAfterEmit, "collapse must not bump the comments revision")

        // Expanding again must also leave the revision untouched.
        vm.toggleCollapse(elementId: parentElementId)
        #expect(!vm.isCollapsed(elementId: parentElementId))
        #expect(vm.commentsRevision == revisionAfterEmit)

        vm.stopObservations()
    }
}
