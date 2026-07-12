//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import Testing
@testable import SpudDataKit

/// Covers the comment delete/restore mutation through the idempotent outbox.
/// Mirrors the hide/save coverage in ``OutboxServiceTests``: enqueue applies the
/// optimistic `isDeleted` write, a successful drain clears the pending row, and a
/// permanent failure rolls `isDeleted` back to the baseline.
@MainActor
struct OutboxCommentDeleteTests {
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
        try await seedPost(appDatabase, accountId: accountId, siteId: siteId, score: 0, voteStatus: nil)
        try await seedComment(
            appDatabase,
            accountId: accountId,
            siteId: siteId,
            commentServerId: 7,
            score: 0,
            voteStatus: nil,
            isDeleted: false
        )
        // Make the network never resolve the row so we can observe the optimistic
        // write standing before the drain reconciles. A transient failure parks
        // the pending row without rolling back.
        let performer = FakeOutboxPerformer()
        await performer.setOutcome(.fail(URLError(.timedOut)), for: .delete)
        let service = makeService(appDatabase, performer, accountId: accountId)

        await service.enqueue(.init(entityType: .comment, entityServerId: 7, desiredState: .delete(true)))

        // Optimistic projection applied immediately.
        let deleted = try await readCommentDeleted(appDatabase, accountId: accountId, serverCommentId: 7)
        #expect(deleted == true)

        // Pending row persisted (transient failure keeps it for retry).
        let rows = try await appDatabase.allOutboxOperations(accountId: accountId)
        #expect(rows.count == 1)
        #expect(rows[0].kind == OutboxKind.delete.rawValue)
        #expect(rows[0].entityType == OutboxEntityType.comment.rawValue)
        // Baseline is the pre-delete state (false -> 0) so a rollback restores it.
        #expect(rows[0].baseline == 0)
    }

    @Test
    func successfulDrainClearsPendingRow() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId) = try await seedAccountAndSite(appDatabase)
        try await seedPost(appDatabase, accountId: accountId, siteId: siteId, score: 0, voteStatus: nil)
        try await seedComment(
            appDatabase,
            accountId: accountId,
            siteId: siteId,
            commentServerId: 7,
            score: 0,
            voteStatus: nil,
            isDeleted: false
        )
        let performer = FakeOutboxPerformer()
        let service = makeService(appDatabase, performer, accountId: accountId)

        await service.enqueue(.init(entityType: .comment, entityServerId: 7, desiredState: .delete(true)))

        let rows = try await appDatabase.allOutboxOperations(accountId: accountId)
        #expect(rows.isEmpty)
        let performed = await performer.performed
        #expect(performed.count == 1)
        #expect(performed.first?.kind == .delete)
        #expect(performed.first?.desiredState == .delete(true))
        // The optimistic delete still stands (the fake performer does not
        // reconcile a response, so the local write is authoritative here).
        let deleted = try await readCommentDeleted(appDatabase, accountId: accountId, serverCommentId: 7)
        #expect(deleted == true)
    }

    @Test
    func permanentFailureRollsBackAndEmits() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId) = try await seedAccountAndSite(appDatabase)
        try await seedPost(appDatabase, accountId: accountId, siteId: siteId, score: 0, voteStatus: nil)
        try await seedComment(
            appDatabase,
            accountId: accountId,
            siteId: siteId,
            commentServerId: 7,
            score: 0,
            voteStatus: nil,
            isDeleted: false
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

        await service.enqueue(.init(entityType: .comment, entityServerId: 7, desiredState: .delete(true)))
        await collector.value

        // Pending row removed, optimistic write rolled back to baseline (not deleted).
        let rows = try await appDatabase.allOutboxOperations(accountId: accountId)
        #expect(rows.isEmpty)
        let deleted = try await readCommentDeleted(appDatabase, accountId: accountId, serverCommentId: 7)
        #expect(deleted == false)
        #expect(events.first?.kind == .delete)
        #expect(events.first?.entityType == .comment)
        #expect(events.first?.entityServerId == 7)
    }

    /// A background comment refresh must not clobber the un-synced optimistic
    /// delete: while a `.delete` op is pending, re-importing the stale server
    /// `CommentView` (deleted=false) preserves the optimistic `isDeleted=true`.
    @Test
    func refreshDoesNotClobberPendingDelete() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId) = try await seedAccountAndSite(appDatabase)
        try await seedPost(appDatabase, accountId: accountId, siteId: siteId, score: 0, voteStatus: nil)
        try await seedComment(
            appDatabase,
            accountId: accountId,
            siteId: siteId,
            commentServerId: 7,
            score: 0,
            voteStatus: nil,
            isDeleted: false
        )

        // Enqueue a delete: optimistic isDeleted becomes true (no drain yet).
        try await appDatabase.enqueueOutboxOperation(
            OutboxOperation(entityType: .comment, entityServerId: 7, desiredState: .delete(true)),
            accountId: accountId,
            now: 100
        )

        // Simulate a background refresh returning the old server state
        // (deleted=false). The guard preserves the optimistic delete.
        let post = Lemmy.Post.fake(creator: .fake, community: .fake)
        let staleComment = Lemmy.Comment.fake(
            id: Lemmy.CommentID(7),
            post: post,
            creator: .fake,
            parent: .root
        )
        let staleView = Lemmy.CommentView.fake(
            comment: staleComment,
            creator: .fake,
            post: post,
            community: .fake,
            childCount: 0
        )
        try await appDatabase.upsertComment(from: staleView, accountId: accountId, siteId: siteId)

        let deleted = try await readCommentDeleted(appDatabase, accountId: accountId, serverCommentId: 7)
        #expect(deleted == true)
    }

    @Test
    func restoreOptimisticallyUndeletes() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId) = try await seedAccountAndSite(appDatabase)
        try await seedPost(appDatabase, accountId: accountId, siteId: siteId, score: 0, voteStatus: nil)
        try await seedComment(
            appDatabase,
            accountId: accountId,
            siteId: siteId,
            commentServerId: 7,
            score: 0,
            voteStatus: nil,
            isDeleted: true
        )
        let performer = FakeOutboxPerformer()
        await performer.setOutcome(.fail(URLError(.timedOut)), for: .delete)
        let service = makeService(appDatabase, performer, accountId: accountId)

        await service.enqueue(.init(entityType: .comment, entityServerId: 7, desiredState: .delete(false)))

        let deleted = try await readCommentDeleted(appDatabase, accountId: accountId, serverCommentId: 7)
        #expect(deleted == false)
        let rows = try await appDatabase.allOutboxOperations(accountId: accountId)
        #expect(rows.count == 1)
        // Baseline captured the prior deleted state (true -> 1).
        #expect(rows[0].baseline == 1)
    }
}
