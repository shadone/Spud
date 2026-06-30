//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import Testing
@testable import SpudDataKit

/// Tests that ``OutboxService`` emits structured diagnostic events at every
/// stage of the drain lifecycle. Covers the three critical paths:
///
/// - **Permanent failure** (`op.permanentRollback`) — the silent discard that was
///   previously invisible in logs; must carry `httpStatus` and `instance`.
/// - **Transient failure** (`op.transientRetry`) — should NOT roll back the pending row.
/// - **Success** (`op.success`) — confirms the happy-path event fires and the row is gone.
///
/// Each test injects a fresh ``DiagnosticLogSpy`` so event assertions are precise
/// and no database I/O or OSLog side-effects occur.
@MainActor
struct OutboxServiceDiagnosticsTests {
    // MARK: - Helpers

    private func makeService(
        _ appDatabase: AppDatabase,
        _ performer: FakeOutboxPerformer,
        online: Bool = true,
        accountId: Int64,
        diagnostics: DiagnosticLogSpy,
        instance: String? = "lemmy.test"
    ) -> OutboxService {
        OutboxService(
            accountId: accountId,
            appDatabase: appDatabase,
            performer: performer,
            reachability: StaticReachabilityMonitor(isOnline: online),
            now: { 1000 },
            diagnostics: diagnostics,
            instance: instance
        )
    }

    // MARK: - Tests

    /// A 403 permanent failure must emit `op.permanentRollback` with `httpStatus == "403"`,
    /// the configured `instance`, and the post's `voteStatus` rolled back to baseline.
    @Test
    func permanentFailureEmitsRollbackEvent() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId) = try await seedAccountAndSite(appDatabase)
        let postId = try await seedPost(appDatabase, accountId: accountId, siteId: siteId, score: 5, voteStatus: nil)
        let performer = FakeOutboxPerformer()
        await performer.setOutcome(
            .fail(LemmyApiError.unknownServerError(httpStatusCode: 403, error: nil)),
            for: .vote
        )
        let spy = DiagnosticLogSpy()
        let service = makeService(appDatabase, performer, accountId: accountId, diagnostics: spy)

        // Collect the first failure event so we can await completion.
        let stream = await service.failureEvents
        let collector = Task {
            for await _ in stream {
                break
            }
        }

        await service.enqueue(.init(entityType: .post, entityServerId: postId, desiredState: .vote(.liked)))
        await collector.value

        // The pending row must be rolled back.
        let rows = try await appDatabase.allOutboxOperations(accountId: accountId)
        #expect(rows.isEmpty, "permanent failure must remove the pending row")

        // The post's voteStatus must be restored to nil (the pre-enqueue baseline).
        let (score, vote) = try await readPostVote(appDatabase, accountId: accountId, serverPostId: postId)
        #expect(score == 5, "score must be restored to baseline")
        #expect(vote == nil, "voteStatus must be rolled back to nil")

        // Exactly one op.permanentRollback event must have been recorded.
        let rollbacks = spy.events(matching: "op.permanentRollback")
        #expect(rollbacks.count == 1, "expected exactly one op.permanentRollback event")

        let rollback = try #require(rollbacks.first)
        #expect(rollback.category == .outbox)
        #expect(rollback.level == .error)
        #expect(rollback.instance == "lemmy.test")
        #expect(rollback.metadata?["httpStatus"] == "403", "httpStatus must be extracted from LemmyApiError")
        #expect(rollback.metadata?["entityType"] == "post")
        #expect(rollback.metadata?["entityServerId"] == String(postId))
    }

    /// A transient failure (URLError offline) must emit `op.transientRetry` and
    /// leave the pending row intact (no rollback).
    @Test
    func transientFailureEmitsRetryEventAndKeepsRow() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId) = try await seedAccountAndSite(appDatabase)
        let postId = try await seedPost(appDatabase, accountId: accountId, siteId: siteId, score: 0, voteStatus: nil)
        let performer = FakeOutboxPerformer()
        await performer.setOutcome(.fail(URLError(.notConnectedToInternet)), for: .vote)
        let spy = DiagnosticLogSpy()
        let service = makeService(appDatabase, performer, online: false, accountId: accountId, diagnostics: spy)

        await service.enqueue(.init(entityType: .post, entityServerId: postId, desiredState: .vote(.liked)))

        // The row must still be present (transient — will be retried).
        let rows = try await appDatabase.allOutboxOperations(accountId: accountId)
        #expect(rows.count == 1, "transient failure must keep the pending row")

        // Exactly one op.transientRetry event.
        let retries = spy.events(matching: "op.transientRetry")
        #expect(retries.count == 1, "expected exactly one op.transientRetry event")

        let retry = try #require(retries.first)
        #expect(retry.category == .outbox)
        #expect(retry.level == .notice)
        #expect(retry.instance == "lemmy.test")
        #expect(retry.metadata?["entityType"] == "post")

        // No rollback event must have been emitted.
        #expect(spy.events(matching: "op.permanentRollback").isEmpty, "transient failure must not emit rollback")
    }

    /// A successful drain must emit `op.success` and remove the pending row.
    @Test
    func successEmitsSuccessEvent() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId) = try await seedAccountAndSite(appDatabase)
        let postId = try await seedPost(appDatabase, accountId: accountId, siteId: siteId, score: 0, voteStatus: nil)
        let performer = FakeOutboxPerformer() // default outcome: .success
        let spy = DiagnosticLogSpy()
        let service = makeService(appDatabase, performer, accountId: accountId, diagnostics: spy)

        await service.enqueue(.init(entityType: .post, entityServerId: postId, desiredState: .vote(.liked)))

        // The pending row must be gone.
        let rows = try await appDatabase.allOutboxOperations(accountId: accountId)
        #expect(rows.isEmpty, "success must remove the pending row")

        // Exactly one op.success event.
        let successes = spy.events(matching: "op.success")
        #expect(successes.count == 1, "expected exactly one op.success event")

        let success = try #require(successes.first)
        #expect(success.category == .outbox)
        #expect(success.level == .info)
        #expect(success.instance == "lemmy.test")
        #expect(success.metadata?["entityType"] == "post")
        #expect(success.metadata?["entityServerId"] == String(postId))

        // No error events.
        #expect(spy.events(matching: "op.permanentRollback").isEmpty)
        #expect(spy.events(matching: "op.transientRetry").isEmpty)
    }
}
