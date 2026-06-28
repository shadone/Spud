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
    /// The records handed to `perform`, in call order, so a test can assert that
    /// an edit row reached the performer (and carried the right edit target).
    private(set) var performedRecords: [OutboundContentRecord] = []
    init(_ mode: Mode) {
        self.mode = mode
    }

    func set(_ m: Mode) {
        mode = m
    }

    func perform(_ record: OutboundContentRecord) async throws -> Int64? {
        calls += 1
        performedRecords.append(record)
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

    /// An edit of comment `serverCommentId` on post 1.
    func makeEditInput(serverCommentId: Int64, body: String = "edited body") -> OutboundDraftInput {
        OutboundDraftInput(
            kind: .comment,
            body: body,
            postServerId: 1,
            parentCommentServerId: nil,
            communityServerId: nil,
            title: nil,
            url: nil,
            nsfw: false,
            postType: 0,
            editCommentServerId: serverCommentId
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

    // MARK: - Edit

    @Test
    func editDrainsByCallingPerformerAndReconciles() async throws {
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
        let token = try await db.upsertOutboundDraft(makeEditInput(serverCommentId: 42), accountId: acc, now: 0)
        try await db.markOutboundQueued(clientToken: token, now: 0)
        await svc.drainOnce()

        // The performer saw exactly the edit record, carrying the edit target.
        #expect(await performer.calls == 1)
        let performed = await performer.performedRecords
        #expect(performed.first?.editCommentServerId == 42)
        #expect(performed.first?.body == "edited body")
        // Success deletes the outbound row and emits success (reconcile is the
        // performer's `upsertComment(respectsPendingOutbox: false)`).
        #expect(try await db.allOutbound(accountId: acc).isEmpty)
        var it = successes.makeAsyncIterator()
        #expect(await it.next()?.clientToken == token)
    }

    @Test
    func editUsesDistinctDraftKeyFromReply() async throws {
        // An edit must not coalesce with a reply draft for the same post/parent.
        let db = try AppDatabase.inMemory()
        let acc = try await OutboundContentMigrationTests.seedAccount(db)
        let replyToken = try await db.upsertOutboundDraft(makeInput(), accountId: acc, now: 0)
        let editToken = try await db.upsertOutboundDraft(makeEditInput(serverCommentId: 7), accountId: acc, now: 0)
        #expect(replyToken != editToken)
        // Both drafts coexist (distinct draftKeys → distinct rows).
        let rows = try await db.allOutbound(accountId: acc)
        #expect(rows.count == 2)
        let editRow = rows.first { $0.editCommentServerId == 7 }
        #expect(editRow?.draftKey == "ec:7")
        let replyRow = rows.first { $0.editCommentServerId == nil }
        #expect(replyRow?.draftKey == "c:1:0")
    }

    @Test
    func editPermanentFailureParksAsFailedKeepingContent() async throws {
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
        let token = try await db.upsertOutboundDraft(makeEditInput(serverCommentId: 9), accountId: acc, now: 0)
        try await db.markOutboundQueued(clientToken: token, now: 0)
        await svc.drainOnce()
        let rows = try await db.allOutbound(accountId: acc)
        // Parked as failed (content kept), exactly like a failed new comment.
        #expect(rows.count == 1)
        #expect(rows.first?.status == OutboundStatus.failed.rawValue)
        #expect(rows.first?.editCommentServerId == 9)
        #expect(rows.first?.body == "edited body")
    }

    @Test
    func dedupSkippedForEdits() async throws {
        // A matching server comment exists (a prior committed-but-lost-response
        // create would be adopted+skipped). An EDIT with the same body must NOT be
        // skipped — it targets an existing comment by design.
        let db = try AppDatabase.inMemory()
        let acc = try await OutboundContentMigrationTests.seedAccount(db)
        try await Self.seedOwnComment(db, accountId: acc, serverCommentId: 99, body: "edited body")

        // Sanity: the dedup query reports a match for this (post, creator, body).
        let matches = try await db.matchingServerCommentExists(
            accountId: acc, postServerId: 1, parentCommentServerId: nil, body: "edited body"
        )
        #expect(matches == true)

        let performer = FakePerformer(.success(nil))
        let svc = ComposerOutboxService(
            accountId: acc,
            appDatabase: db,
            performer: performer,
            reachability: FakeReachability(),
            now: { 0 }
        )
        let token = try await db.upsertOutboundDraft(
            makeEditInput(serverCommentId: 99, body: "edited body"), accountId: acc, now: 0
        )
        try await db.markOutboundQueued(clientToken: token, now: 0)
        await svc.drainOnce()

        // Despite the matching server comment, the edit reached the performer
        // (dedup was skipped) and then drained to completion.
        #expect(await performer.calls == 1)
        #expect(try await db.allOutbound(accountId: acc).isEmpty)
    }

    @Test
    func dedupAdoptsMatchingCreate() async throws {
        // Counterpart to dedupSkippedForEdits: a CREATE with a body matching an
        // existing server comment is adopted+skipped (never sent).
        let db = try AppDatabase.inMemory()
        let acc = try await OutboundContentMigrationTests.seedAccount(db)
        try await Self.seedOwnComment(db, accountId: acc, serverCommentId: 99, body: "hi")

        let performer = FakePerformer(.success(nil))
        let svc = ComposerOutboxService(
            accountId: acc,
            appDatabase: db,
            performer: performer,
            reachability: FakeReachability(),
            now: { 0 }
        )
        let token = try await db.upsertOutboundDraft(makeInput(), accountId: acc, now: 0) // body "hi"
        try await db.markOutboundQueued(clientToken: token, now: 0)
        await svc.drainOnce()

        #expect(await performer.calls == 0) // adopted, never sent
        #expect(try await db.allOutbound(accountId: acc).isEmpty) // row removed
    }

    /// Seeds a post + a comment authored by the account's own person, and points
    /// `account.personId` at that person so `matchingServerCommentExists`'s
    /// account→person join resolves. Mirrors the FK shape other suites seed.
    static func seedOwnComment(
        _ db: AppDatabase, accountId: Int64, serverCommentId: Int64, body: String
    ) async throws {
        let now = Date()
        try await db.writer.write { write in
            let siteId = try Int64.fetchOne(write, sql: "SELECT siteId FROM account WHERE id = ?", arguments: [accountId])!
            // Person (the comment author == the account owner).
            try write.execute(sql: """
                INSERT INTO person
                    (siteId, personId, isAdmin, isBanned, isBotAccount, isDeleted, isLocal,
                     numberOfPosts, numberOfComments, createdAt, updatedAt)
                VALUES (?, 1, 0, 0, 0, 0, 1, 0, 0, ?, ?)
                """, arguments: [siteId, now, now])
            let personRowId = write.lastInsertedRowID
            // Point the account at this person (the join key is personId, not row id).
            try write.execute(
                sql: "UPDATE account SET personId = 1 WHERE id = ?", arguments: [accountId]
            )
            // Community (post FK).
            try write.execute(sql: """
                INSERT INTO community
                    (accountId, communityId, isHidden, isLocal, isNsfw, isPostingRestrictedToMods,
                     isRemoved, subscribedState, numberOfSubscribers, numberOfPosts,
                     numberOfComments, createdAt, updatedAt)
                VALUES (?, 1, 0, 1, 0, 0, 0, 'NotSubscribed', 0, 0, 0, ?, ?)
                """, arguments: [accountId, now, now])
            let communityRowId = write.lastInsertedRowID
            // Post (server id 1) authored by the person.
            try write.execute(sql: """
                INSERT INTO post
                    (accountId, communityId, creatorId, postId, title, originalPostUrl,
                     score, numberOfUpvotes, numberOfDownvotes, numberOfComments,
                     isRead, isSaved, isHidden, isRemoved, isLocked,
                     isFeaturedCommunity, isFeaturedLocal, isDeleted,
                     published, createdAt, updatedAt)
                VALUES (?, ?, ?, 1, 'T', 'https://example.com/post/1', 0, 0, 0, 0,
                        0, 0, 0, 0, 0, 0, 0, 0, ?, ?, ?)
                """, arguments: [accountId, communityRowId, personRowId, now, now, now])
            let postRowId = write.lastInsertedRowID
            // Comment authored by the person, with the given server id + body.
            try write.execute(sql: """
                INSERT INTO comment
                    (postId, creatorId, localCommentId, body, score, numberOfUpvotes,
                     numberOfDownvotes, published, createdAt, updatedAt, isSaved,
                     isRemoved, isDistinguished, isDeleted, isCreatorModerator,
                     isCreatorAdmin, isCreatorBannedFromCommunity, isCreatorBlocked)
                VALUES (?, ?, ?, ?, 0, 0, 0, ?, ?, ?, 0, 0, 0, 0, 0, 0, 0, 0)
                """, arguments: [postRowId, personRowId, serverCommentId, body, now, now, now])
        }
    }
}
