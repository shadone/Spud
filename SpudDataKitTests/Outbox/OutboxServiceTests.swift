//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import Testing
@testable import SpudDataKit

@MainActor
struct OutboxServiceTests {
    func makeService(
        _ appDatabase: AppDatabase,
        _ performer: FakeOutboxPerformer,
        online: Bool = true,
        accountId: Int64 = 1,
        diagnostics: DiagnosticLogging = DiagnosticLogSpy(),
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

    @Test
    func successfulDrainRemovesRow() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId) = try await seedAccountAndSite(appDatabase)
        let postId = try await seedPost(appDatabase, accountId: accountId, siteId: siteId, score: 0, voteStatus: nil)
        let performer = FakeOutboxPerformer()
        let service = makeService(appDatabase, performer, accountId: accountId)

        await service.enqueue(.init(entityType: .post, entityServerId: postId, desiredState: .vote(.liked)))

        let rows = try await appDatabase.allOutboxOperations(accountId: accountId)
        #expect(rows.isEmpty)
        let performedCount = await performer.performed.count
        #expect(performedCount == 1)
    }

    @Test
    func transientFailureKeepsRowAndSchedulesRetry() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId) = try await seedAccountAndSite(appDatabase)
        let postId = try await seedPost(appDatabase, accountId: accountId, siteId: siteId, score: 0, voteStatus: nil)
        let performer = FakeOutboxPerformer()
        await performer.setOutcome(.fail(URLError(.timedOut)), for: .vote)
        let service = makeService(appDatabase, performer, accountId: accountId)

        await service.enqueue(.init(entityType: .post, entityServerId: postId, desiredState: .vote(.liked)))

        let rows = try await appDatabase.allOutboxOperations(accountId: accountId)
        #expect(rows.count == 1)
        #expect(rows[0].attempts == 1)
        #expect((rows[0].nextAttemptAt ?? 0) > 1000)
    }

    @Test
    func permanentFailureRollsBackAndEmits() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId) = try await seedAccountAndSite(appDatabase)
        let postId = try await seedPost(appDatabase, accountId: accountId, siteId: siteId, score: 5, voteStatus: nil)
        let performer = FakeOutboxPerformer()
        await performer.setOutcome(.fail(LemmyServiceError.requiresAuthentication), for: .vote)
        let service = makeService(appDatabase, performer, accountId: accountId)

        var events: [OutboxFailure] = []
        let stream = await service.failureEvents
        let collector = Task { for await event in stream {
            events.append(event)
            break
        } }

        await service.enqueue(.init(entityType: .post, entityServerId: postId, desiredState: .vote(.liked)))
        await collector.value

        let rows = try await appDatabase.allOutboxOperations(accountId: accountId)
        #expect(rows.isEmpty)
        let (score, vote) = try await readPostVote(appDatabase, accountId: accountId, serverPostId: postId)
        #expect(score == 5)
        #expect(vote == nil)
        #expect(events.first?.kind == .vote)
    }

    @Test
    func nonNotFoundPermanentFailureReportsReasonOther() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId) = try await seedAccountAndSite(appDatabase)
        let postId = try await seedPost(appDatabase, accountId: accountId, siteId: siteId, score: 5, voteStatus: nil)
        let performer = FakeOutboxPerformer()
        await performer.setOutcome(.fail(LemmyServiceError.requiresAuthentication), for: .vote)
        let service = makeService(appDatabase, performer, accountId: accountId)

        var events: [OutboxFailure] = []
        let stream = await service.failureEvents
        let collector = Task { for await event in stream {
            events.append(event)
            break
        } }
        await service.enqueue(.init(entityType: .post, entityServerId: postId, desiredState: .vote(.liked)))
        _ = await collector.value

        #expect(events.count == 1)
        #expect(events[0].reason == .other)
    }

    @Test
    func notFoundVoteMarksPostUnavailableAndReportsReason() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId) = try await seedAccountAndSite(appDatabase)
        let postId = try await seedPost(appDatabase, accountId: accountId, siteId: siteId, score: 5, voteStatus: nil)
        let performer = FakeOutboxPerformer()
        let notFound = LemmyApiError.serverError(
            Components.Schemas.ErrorResponse(error: "couldnt_find_post", message: nil)
        )
        await performer.setOutcome(.fail(notFound), for: .vote)
        let service = makeService(appDatabase, performer, accountId: accountId)

        var events: [OutboxFailure] = []
        let stream = await service.failureEvents
        let collector = Task { for await event in stream {
            events.append(event)
            break
        } }

        await service.enqueue(.init(entityType: .post, entityServerId: postId, desiredState: .vote(.liked)))
        _ = await collector.value

        #expect(try await readPostUnavailable(appDatabase, accountId: accountId, serverPostId: postId) == true)
        #expect(events.count == 1)
        #expect(events[0].reason == .notFound)
        #expect(events[0].kind == .vote)
    }
}
