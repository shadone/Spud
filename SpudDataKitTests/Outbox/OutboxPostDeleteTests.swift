//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import Testing
@testable import SpudDataKit

/// Covers delete/restore of the user's OWN post through the idempotent outbox.
/// Mirrors ``OutboxCommentDeleteTests`` (the comment equivalent): enqueue applies
/// the optimistic `isDeleted` write, a successful drain clears the pending row, a
/// permanent failure rolls `isDeleted` back to the baseline, and a stale refresh
/// does not clobber an un-synced pending delete.
@MainActor
struct OutboxPostDeleteTests {
    func makeService(
        _ appDatabase: AppDatabase,
        _ performer: FakeOutboxPerformer,
        online: Bool = true,
        accountId: Int64 = 1
    ) -> OutboxService {
        OutboxService(
            accountId: accountId,
            appDatabase: appDatabase,
            performer: performer,
            reachability: StaticReachabilityMonitor(isOnline: online),
            now: { 1000 },
            diagnostics: DiagnosticLogSpy(),
            instance: "lemmy.test"
        )
    }

    @Test
    func enqueueAppliesOptimisticDelete() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId) = try await seedAccountAndSite(appDatabase)
        let serverPostId = try await seedPost(
            appDatabase, accountId: accountId, siteId: siteId, score: 0, voteStatus: nil, isDeleted: false
        )
        // A transient failure parks the pending row without rolling back, so the
        // optimistic write stands for inspection.
        let performer = FakeOutboxPerformer()
        await performer.setOutcome(.fail(URLError(.timedOut)), for: .delete)
        let service = makeService(appDatabase, performer, accountId: accountId)

        await service.enqueue(.init(entityType: .post, entityServerId: serverPostId, desiredState: .delete(true)))

        let deleted = try await readPostDeleted(appDatabase, accountId: accountId, serverPostId: serverPostId)
        #expect(deleted == true)

        let rows = try await appDatabase.allOutboxOperations(accountId: accountId)
        #expect(rows.count == 1)
        #expect(rows[0].kind == OutboxKind.delete.rawValue)
        #expect(rows[0].entityType == OutboxEntityType.post.rawValue)
        // Baseline is the pre-delete state (false -> 0) so a rollback restores it.
        #expect(rows[0].baseline == 0)
    }

    @Test
    func successfulDrainClearsPendingRow() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId) = try await seedAccountAndSite(appDatabase)
        let serverPostId = try await seedPost(
            appDatabase, accountId: accountId, siteId: siteId, score: 0, voteStatus: nil, isDeleted: false
        )
        let performer = FakeOutboxPerformer()
        let service = makeService(appDatabase, performer, accountId: accountId)

        await service.enqueue(.init(entityType: .post, entityServerId: serverPostId, desiredState: .delete(true)))

        let rows = try await appDatabase.allOutboxOperations(accountId: accountId)
        #expect(rows.isEmpty)
        let performed = await performer.performed
        #expect(performed.count == 1)
        #expect(performed.first?.kind == .delete)
        #expect(performed.first?.entityType == .post)
        #expect(performed.first?.desiredState == .delete(true))
        let deleted = try await readPostDeleted(appDatabase, accountId: accountId, serverPostId: serverPostId)
        #expect(deleted == true)
    }

    @Test
    func permanentFailureRollsBackAndEmits() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId) = try await seedAccountAndSite(appDatabase)
        let serverPostId = try await seedPost(
            appDatabase, accountId: accountId, siteId: siteId, score: 0, voteStatus: nil, isDeleted: false
        )
        let performer = FakeOutboxPerformer()
        await performer.setOutcome(.fail(LemmyServiceError.requiresAuthentication), for: .delete)
        let service = makeService(appDatabase, performer, accountId: accountId)

        var events: [OutboxFailure] = []
        let stream = await service.failureEvents
        let collector = Task { for await event in stream {
            events.append(event)
            break
        } }

        await service.enqueue(.init(entityType: .post, entityServerId: serverPostId, desiredState: .delete(true)))
        await collector.value

        let rows = try await appDatabase.allOutboxOperations(accountId: accountId)
        #expect(rows.isEmpty)
        let deleted = try await readPostDeleted(appDatabase, accountId: accountId, serverPostId: serverPostId)
        #expect(deleted == false)
        #expect(events.first?.kind == .delete)
        #expect(events.first?.entityType == .post)
        #expect(events.first?.entityServerId == serverPostId)
    }

    /// A background post refresh must not clobber the un-synced optimistic delete:
    /// while a `.delete` op is pending, re-importing the stale server `PostView`
    /// (deleted=false) preserves the optimistic `isDeleted=true`.
    @Test
    func refreshDoesNotClobberPendingDelete() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId) = try await seedAccountAndSite(appDatabase)
        let serverPostId = try await seedPost(
            appDatabase, accountId: accountId, siteId: siteId, score: 0, voteStatus: nil, isDeleted: false
        )

        try await appDatabase.enqueueOutboxOperation(
            OutboxOperation(entityType: .post, entityServerId: serverPostId, desiredState: .delete(true)),
            accountId: accountId,
            now: 100
        )

        // Re-import the same post with the stale server state (deleted=false).
        let post = Lemmy.Post.fake(creator: .fake, community: .fake)
        let staleView = Lemmy.PostView.fake(post: post, creator: .fake, community: .fake)
        try await appDatabase.upsertPost(from: staleView, accountId: accountId, siteId: siteId)

        let deleted = try await readPostDeleted(appDatabase, accountId: accountId, serverPostId: serverPostId)
        #expect(deleted == true)
    }

    @Test
    func restoreOptimisticallyUndeletes() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId) = try await seedAccountAndSite(appDatabase)
        let serverPostId = try await seedPost(
            appDatabase, accountId: accountId, siteId: siteId, score: 0, voteStatus: nil, isDeleted: true
        )
        let performer = FakeOutboxPerformer()
        await performer.setOutcome(.fail(URLError(.timedOut)), for: .delete)
        let service = makeService(appDatabase, performer, accountId: accountId)

        await service.enqueue(.init(entityType: .post, entityServerId: serverPostId, desiredState: .delete(false)))

        let deleted = try await readPostDeleted(appDatabase, accountId: accountId, serverPostId: serverPostId)
        #expect(deleted == false)
        let rows = try await appDatabase.allOutboxOperations(accountId: accountId)
        #expect(rows.count == 1)
        // Baseline captured the prior deleted state (true -> 1).
        #expect(rows[0].baseline == 1)
    }
}
