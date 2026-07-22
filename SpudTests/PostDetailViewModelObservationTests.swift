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
        /// The seeded creator person's server-side person id. When the seed
        /// links the account to this person (``makeSeed(linkAccountToOwnPerson:)``)
        /// it is the account's OWN person id, so `isOwnContent(creatorPersonId:)`
        /// is true for it and false for any other id.
        let creatorServerPersonId: Int64
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
        preOpenedAt: Date? = nil,
        linkAccountToOwnPerson: Bool = false
    ) async throws -> Seed {
        let appDatabase = try AppDatabase.inMemory()
        let creatorServerPersonId: Int64 = 99

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
                personId: creatorServerPersonId,
                name: "seededcreator",
                actorId: "https://example.com/u/seededcreator"
            )
            try creator.insert(db)

            // Optionally make the account's OWN person the seeded creator, so
            // `accountOwnPersonIdsSync` resolves and `isOwnContent` is true for
            // `creatorServerPersonId`. Left unset (nil) the account has no own
            // person — the signed-out / unresolved case.
            if linkAccountToOwnPerson {
                account.personId = creator.id
                try account.update(db)
            }

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
            creatorServerPersonId: creatorServerPersonId,
            title: title,
            body: body
        )
    }

    /// Inserts one outbound (pending/failed/draft) comment row for the seeded
    /// post + account, so the outbound observation the view model owns picks it
    /// up. Returns the created row id. Can run before or after
    /// ``PostDetailViewModel/startObservations()`` — a live write re-fires the
    /// observation.
    @discardableResult
    private func seedOutbound(
        _ seed: Seed,
        status: OutboundStatus,
        body: String,
        clientToken: String
    ) async throws -> Int64 {
        try await seed.appDatabase.writer.write { db -> Int64 in
            let now = Date().timeIntervalSince1970
            var record = OutboundContentRecord(
                id: nil,
                clientToken: clientToken,
                accountId: seed.accountId,
                kind: OutboundKind.comment.rawValue,
                status: status.rawValue,
                draftKey: OutboundContentRecord.commentDraftKey(
                    postServerId: seed.serverPostId,
                    parentCommentServerId: nil
                ),
                body: body,
                postServerId: seed.serverPostId,
                parentCommentServerId: nil,
                communityServerId: nil,
                title: nil,
                url: nil,
                nsfw: false,
                postType: 0,
                editCommentServerId: nil,
                editPostServerId: nil,
                recipientServerPersonId: nil,
                attempts: 0,
                lastError: nil,
                nextAttemptAt: nil,
                createdAt: now,
                updatedAt: now
            )
            try record.insert(db)
            return record.id!
        }
    }

    /// Seeds one cross-post: another post under `communityName` (a fresh
    /// community row under the same account) plus the `postCrossPost` junction
    /// row linking it to the seeded post at `position`. Mirrors what
    /// `LemmyService.fetchPostInfo`'s harvest would have written on a prior
    /// fetch.
    @discardableResult
    private func seedCrossPost(
        _ seed: Seed,
        serverPostId: Int64,
        communityName: String,
        position: Int64
    ) async throws -> Int64 {
        try await seed.appDatabase.writer.write { db -> Int64 in
            var community = CommunityRecord(
                accountId: seed.accountId,
                communityId: 100 + serverPostId,
                name: communityName,
                actorId: "https://example.com/c/\(communityName)"
            )
            try community.insert(db)

            var crossPost = PostRecord(
                accountId: seed.accountId,
                communityId: community.id!,
                creatorId: seed.creatorRowId,
                postId: serverPostId,
                title: "Cross-post in \(communityName)",
                originalPostUrl: "https://example.com/post/\(serverPostId)",
                published: Date(timeIntervalSince1970: 1_000_000)
            )
            try crossPost.insert(db)

            var junction = PostCrossPostRecord(
                postId: seed.postRowId,
                crossPostId: crossPost.id!,
                position: position
            )
            try junction.insert(db)
            return crossPost.id!
        }
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
            serverPostId: Lemmy.PostID(seed.serverPostId),
            accountScope: seed.dependencies.accountService.scope(forAccountKeychainId: seed.keychainId),
            appDatabase: seed.appDatabase,
            dependencies: seed.dependencies,
            // Neutralize the network comment fetch the observation bring-up
            // kicks; these tests exercise the header observation + visit
            // recording only.
            fetchCommentsOperation: { _ in .complete }
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
            serverPostId: Lemmy.PostID(seed.serverPostId + 1), // unmirrored id
            accountScope: seed.dependencies.accountService.scope(forAccountKeychainId: seed.keychainId),
            appDatabase: seed.appDatabase,
            dependencies: seed.dependencies,
            fetchCommentsOperation: { _ in
                fetchCount += 1
                return .complete
            }
        )

        vm.startObservations()

        #expect(vm.postRowId == nil)
        // `didPrepareObservation` schedules the fetch on a Task; let it run.
        await poll { fetchCount > 0 }
        #expect(fetchCount == 1)
        #expect(vm.headerRow == nil)

        vm.stopObservations()
    }

    // MARK: - Cross-posts (one-shot read)

    @Test
    func startObservationsPublishesSeededCrossPostsInPositionOrder() async throws {
        let seed = try await makeSeed()

        // Seed out of position order (community "beta" at position 0, "alpha"
        // at position 1) - the published order must follow `position`, not
        // insertion order.
        try await seedCrossPost(seed, serverPostId: 201, communityName: "beta", position: 0)
        try await seedCrossPost(seed, serverPostId: 202, communityName: "alpha", position: 1)

        let vm = makeViewModel(seed)
        #expect(vm.crossPosts.isEmpty, "nothing read before startObservations")

        vm.startObservations()

        #expect(vm.crossPosts.map(\.serverPostId) == [201, 202])
        #expect(vm.crossPosts.map(\.communityName) == ["beta", "alpha"])

        vm.stopObservations()
    }

    @Test
    func startObservationsLeavesCrossPostsEmptyWhenPostHasNone() async throws {
        let seed = try await makeSeed()
        let vm = makeViewModel(seed)

        vm.startObservations()

        #expect(vm.crossPosts.isEmpty)

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
    func commentRowLookupIsBuiltInTheSameTurnAsOrderedComments() async throws {
        // The element-id lookup lives on the view model and is rebuilt inside
        // `updateOrderedComments` in the same synchronous turn that stores the
        // tree, so the two can never drift (the reason the lookup was moved off
        // the view controller). Assert both together right after each emit lands.
        let seed = try await makeSeed()
        let vm = makeViewModel(seed)
        let sortType = vm.commentSortType.rawValue

        // Precondition: no tree, no lookup before any emit.
        #expect(vm.orderedComments.isEmpty)
        #expect(vm.commentRowsByElementId.isEmpty)

        let elementIds = try await seedComments(seed, sortType: sortType, specs: [
            CommentSpec(localId: 101, position: 0, depth: 1, body: "first"),
            CommentSpec(localId: 102, position: 1, depth: 1, body: "second"),
        ])

        vm.startObservations()
        await poll { vm.orderedComments.count == 2 }

        // Everything below is synchronous (no `await`), so no queued observation
        // can interleave between the tree and lookup assertions. The lookup must
        // hold exactly the emitted rows, keyed by element id.
        #expect(vm.orderedComments.count == 2)
        #expect(vm.commentRowsByElementId.count == 2)
        #expect(Set(vm.commentRowsByElementId.keys) == Set(elementIds))
        for row in vm.orderedComments {
            #expect(vm.commentRowsByElementId[row.id]?.serverCommentId == row.serverCommentId)
            #expect(vm.commentRowsByElementId[row.id]?.body == row.body)
        }

        // A second, live DB write must advance BOTH together.
        let moreIds = try await seedComments(seed, sortType: sortType, specs: [
            CommentSpec(localId: 103, position: 2, depth: 1, body: "third-live"),
        ])
        await poll { vm.orderedComments.count == 3 }

        #expect(vm.commentRowsByElementId.count == 3)
        #expect(Set(vm.commentRowsByElementId.keys) == Set(elementIds + moreIds))
        let liveElementId = try #require(moreIds.first)
        #expect(vm.commentRowsByElementId[liveElementId]?.body == "third-live")

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

    // MARK: - Outbound (pending/failed) observation

    @Test
    func startObservationsPublishesSeededOutboundRowAndExcludesDrafts() async throws {
        let seed = try await makeSeed()
        let vm = makeViewModel(seed)

        // Precondition: nothing observed yet.
        #expect(vm.pendingOutboundComments.isEmpty)

        // A pending (queued) row must surface; a draft row must NOT (drafts are
        // unsent compose-bar text, never shown inline).
        try await seedOutbound(seed, status: .queued, body: "pending reply", clientToken: "tok-queued")
        try await seedOutbound(seed, status: .draft, body: "draft reply", clientToken: "tok-draft")

        vm.startObservations()

        await poll { vm.pendingOutboundComments.count == 1 }

        let published = vm.pendingOutboundComments
        #expect(published.count == 1, "only the non-draft row is published")
        #expect(published.first?.body == "pending reply")
        #expect(published.first?.status == OutboundStatus.queued.rawValue)

        vm.stopObservations()
    }

    @Test
    func outboundRowWrittenMidObservationUpdatesPublishedRows() async throws {
        let seed = try await makeSeed()
        let vm = makeViewModel(seed)

        try await seedOutbound(seed, status: .queued, body: "first pending", clientToken: "tok-1")

        vm.startObservations()
        await poll { vm.pendingOutboundComments.count == 1 }
        #expect(vm.pendingOutboundComments.first?.body == "first pending")

        // Write a second pending row while the observation is live: it must
        // re-fire and the published array must grow to include it, in
        // createdAt order.
        try await seedOutbound(seed, status: .failed, body: "second pending", clientToken: "tok-2")

        await poll { vm.pendingOutboundComments.count == 2 }
        #expect(vm.pendingOutboundComments.map(\.body) == ["first pending", "second pending"])
        #expect(vm.pendingOutboundComments.last?.status == OutboundStatus.failed.rawValue)

        vm.stopObservations()
    }

    // MARK: - isOwnContent accessor

    @Test
    func isOwnContentIsTrueForOwnPersonAndFalseForOthers() async throws {
        // The account's own person IS the seeded creator, so its server person id
        // is "own"; any other id (or a nil creator) is not.
        let seed = try await makeSeed(linkAccountToOwnPerson: true)
        let vm = makeViewModel(seed)

        #expect(vm.isOwnContent(creatorPersonId: seed.creatorServerPersonId))
        #expect(!vm.isOwnContent(creatorPersonId: seed.creatorServerPersonId + 1))
        #expect(!vm.isOwnContent(creatorPersonId: nil))
    }

    @Test
    func isOwnContentIsFalseWhenAccountHasNoResolvedOwnPerson() async throws {
        // No account -> person link (the signed-out / unresolved case):
        // `accountOwnPersonIdsSync` returns nil, so nothing is "own" — not even
        // the creator's own server person id.
        let seed = try await makeSeed()
        let vm = makeViewModel(seed)

        #expect(!vm.isOwnContent(creatorPersonId: seed.creatorServerPersonId))
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
}
