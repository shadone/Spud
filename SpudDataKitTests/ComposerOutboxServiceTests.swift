//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudDataKit

private actor FakePerformer: OutboundContentPerforming {
    enum Mode { case success(Int64?), slowSuccess(Int64?), throwTransient, throwPermanent }
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
        case let .slowSuccess(id):
            // Suspend long enough that a concurrent drain can interleave and
            // re-select the still-`sending` row, exercising the in-flight guard.
            for _ in 0..<8 {
                await Task.yield()
            }
            return id
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
        try await db.markOutboundQueued(clientToken: token, now: 0)
        await svc.drainOnce()
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
        try await db.markOutboundQueued(clientToken: token, now: 0)
        await svc.drainOnce()
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
        try await db.markOutboundQueued(clientToken: token, now: 0)
        await svc.drainOnce()
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
        try await db.markOutboundQueued(clientToken: token, now: 0)
        await svc.drainOnce()
        await performer.set(.success(nil))
        try await db.markOutboundQueued(clientToken: token, now: 0)
        await svc.drainOnce()
        #expect(try await db.allOutbound(accountId: acc).isEmpty)
    }

    @Test
    func inFlightGuardPreventsDoubleSend() async throws {
        let db = try AppDatabase.inMemory()
        let acc = try await OutboundContentMigrationTests.seedAccount(db)
        // A deliberately slow send so two concurrent drains overlap on the same
        // `sending` row; the in-flight guard must let only one through.
        let performer = FakePerformer(.slowSuccess(nil))
        let svc = ComposerOutboxService(
            accountId: acc,
            appDatabase: db,
            performer: performer,
            reachability: FakeReachability(),
            now: { 0 }
        )
        let token = try await db.upsertOutboundDraft(makeInput(), accountId: acc, now: 0)
        try await db.markOutboundQueued(clientToken: token, now: 0)

        // Two concurrent drains race on the single queued row.
        async let a: Void = svc.drainOnce()
        async let b: Void = svc.drainOnce()
        _ = await (a, b)

        #expect(await performer.calls == 1) // sent exactly once, no duplicate
        #expect(try await db.allOutbound(accountId: acc).isEmpty) // row deleted on success
    }

    @Test
    func backoffGrowsAndCaps() {
        #expect(ComposerOutboxService.composerBackoffDelay(attempts: 1) == 2)
        #expect(ComposerOutboxService.composerBackoffDelay(attempts: 2) == 4)
        #expect(ComposerOutboxService.composerBackoffDelay(attempts: 20) == 300)
    }
}
