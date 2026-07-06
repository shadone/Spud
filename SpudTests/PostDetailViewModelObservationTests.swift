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
/// in-memory database with the minimal rows the header observation + visit
/// recording need (instance / site / account / community / creator / post), then
/// asserts the view model publishes `headerRow` and records the visit through the
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
        let title: String
        let body: String?
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

        let (accountId, postRowId) = try await appDatabase.writer.write { db -> (Int64, Int64) in
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

            return (account.id!, post.id!)
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
            title: title,
            body: body
        )
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
}
