//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudDataKit

private actor FakePerformer: OutboundContentPerforming {
    enum Mode { case success(Int64?), throwTransient, throwPermanent }
    var mode: Mode
    private(set) var calls = 0
    init(_ mode: Mode) {
        self.mode = mode
    }

    func set(_ m: Mode) {
        mode = m
    }

    func perform(_ record: OutboundContentRecord) async throws -> Int64? {
        calls += 1
        switch mode {
        case let .success(id): return id
        case .throwTransient: throw URLError(.notConnectedToInternet)
        case .throwPermanent: throw LemmyServiceError.requiresAuthentication
        }
    }
}

private final class FakeReachability: ReachabilityMonitoring, @unchecked Sendable {
    @MainActor var isOnline: Bool = true
    @MainActor var statusStream: AsyncStream<Bool> {
        AsyncStream { $0.finish() }
    }
}

struct ComposerOutboxServiceTests {
    func makeInput() -> OutboundDraftInput {
        OutboundDraftInput(
            kind: .comment,
            body: "hi",
            postServerId: 1,
            parentCommentServerId: nil,
            communityServerId: nil,
            title: nil,
            url: nil,
            nsfw: false,
            postType: 0
        )
    }

    @Test
    func successDeletesRowAndEmitsSuccess() async throws {
        let db = try AppDatabase.inMemory()
        let acc = try await OutboundContentMigrationTests.seedAccount(db)
        let performer = FakePerformer(.success(nil))
        let svc = ComposerOutboxService(
            accountId: acc,
            appDatabase: db,
            performer: performer,
            reachability: FakeReachability(),
            now: { 0 }
        )
        let successes = await svc.successEvents
        let token = try await db.upsertOutboundDraft(makeInput(), accountId: acc, now: 0)
        await svc.submit(clientToken: token)
        #expect(try await db.allOutbound(accountId: acc).isEmpty)
        var it = successes.makeAsyncIterator()
        let event = await it.next()
        #expect(event?.clientToken == token)
    }

    @Test
    func transientFailureRequeuesWithBackoff() async throws {
        let db = try AppDatabase.inMemory()
        let acc = try await OutboundContentMigrationTests.seedAccount(db)
        let performer = FakePerformer(.throwTransient)
        let svc = ComposerOutboxService(
            accountId: acc,
            appDatabase: db,
            performer: performer,
            reachability: FakeReachability(),
            now: { 0 }
        )
        let token = try await db.upsertOutboundDraft(makeInput(), accountId: acc, now: 0)
        await svc.submit(clientToken: token)
        let rows = try await db.allOutbound(accountId: acc)
        #expect(rows.count == 1)
        #expect(rows.first?.status == OutboundStatus.queued.rawValue) // still retryable
        #expect((rows.first?.nextAttemptAt ?? 0) > 0) // backoff scheduled
        #expect(rows.first?.attempts == 1)
    }

    @Test
    func permanentFailureParksAsFailedAndEmitsFailure() async throws {
        let db = try AppDatabase.inMemory()
        let acc = try await OutboundContentMigrationTests.seedAccount(db)
        let performer = FakePerformer(.throwPermanent)
        let svc = ComposerOutboxService(
            accountId: acc,
            appDatabase: db,
            performer: performer,
            reachability: FakeReachability(),
            now: { 0 }
        )
        let failures = await svc.failureEvents
        let token = try await db.upsertOutboundDraft(makeInput(), accountId: acc, now: 0)
        await svc.submit(clientToken: token)
        let rows = try await db.allOutbound(accountId: acc)
        #expect(rows.first?.status == OutboundStatus.failed.rawValue) // kept, not deleted
        var it = failures.makeAsyncIterator()
        #expect(await it.next()?.clientToken == token)
    }

    @Test
    func retryFlipsFailedBackToQueuedAndSends() async throws {
        let db = try AppDatabase.inMemory()
        let acc = try await OutboundContentMigrationTests.seedAccount(db)
        let performer = FakePerformer(.throwPermanent)
        let svc = ComposerOutboxService(
            accountId: acc,
            appDatabase: db,
            performer: performer,
            reachability: FakeReachability(),
            now: { 0 }
        )
        let token = try await db.upsertOutboundDraft(makeInput(), accountId: acc, now: 0)
        await svc.submit(clientToken: token)
        await performer.set(.success(nil))
        await svc.retry(clientToken: token)
        #expect(try await db.allOutbound(accountId: acc).isEmpty)
    }

    @Test
    func backoffGrowsAndCaps() {
        #expect(ComposerOutboxService.composerBackoffDelay(attempts: 1) == 2)
        #expect(ComposerOutboxService.composerBackoffDelay(attempts: 2) == 4)
        #expect(ComposerOutboxService.composerBackoffDelay(attempts: 20) == 300)
    }
}
