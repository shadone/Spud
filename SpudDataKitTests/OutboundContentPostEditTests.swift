//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import LemmyKit
import Testing
@testable import SpudDataKit

/// Records the outbound rows handed to `perform`, in call order, so a test can
/// assert that a post-edit row reached the performer carrying the right target.
private actor RecordingPerformer: OutboundContentPerforming {
    private(set) var calls = 0
    private(set) var performedRecords: [OutboundContentRecord] = []
    private let result: Int64?

    init(result: Int64?) {
        self.result = result
    }

    func perform(_ record: OutboundContentRecord) async throws -> Int64? {
        calls += 1
        performedRecords.append(record)
        return result
    }
}

private final class FakeReachability: ReachabilityMonitoring, @unchecked Sendable {
    @MainActor var isOnline: Bool = true
    @MainActor var statusStream: AsyncStream<Bool> {
        AsyncStream { $0.finish() }
    }
}

struct OutboundContentPostEditTests {
    /// A new post create (no edit target).
    private func makeCreateInput(communityServerId: Int64 = 1, body: String = "hi") -> OutboundDraftInput {
        OutboundDraftInput(
            kind: .post,
            body: body,
            postServerId: nil,
            parentCommentServerId: nil,
            communityServerId: communityServerId,
            title: "T",
            url: nil,
            nsfw: false,
            postType: 0
        )
    }

    /// An edit of post `serverPostId`.
    private func makeEditInput(
        serverPostId: Int64,
        title: String = "Edited title",
        body: String = "Edited body"
    ) -> OutboundDraftInput {
        OutboundDraftInput(
            kind: .post,
            body: body,
            postServerId: nil,
            parentCommentServerId: nil,
            communityServerId: 1,
            title: title,
            url: nil,
            nsfw: false,
            postType: 0,
            editPostServerId: serverPostId
        )
    }

    // MARK: - Schema / record

    @Test
    func editPostServerIdColumnExistsAfterV22() async throws {
        let db = try AppDatabase.inMemory()
        let columns = try await db.writer.read { db in
            try db.columns(in: "outboundContent").map(\.name)
        }
        #expect(columns.contains("editPostServerId"))
    }

    @Test
    func editPostServerIdRoundTrips() async throws {
        let db = try AppDatabase.inMemory()
        let accountId = try await OutboundContentMigrationTests.seedAccount(db)
        let token = try await db.upsertOutboundDraft(makeEditInput(serverPostId: 77), accountId: accountId, now: 0)
        let fetched = try await db.writer.read { db in
            try OutboundContentRecord.filter(Column("clientToken") == token).fetchOne(db)
        }
        #expect(fetched?.editPostServerId == 77)
        #expect(fetched?.draftKey == "ep:77")
    }

    @Test
    func editUsesDistinctDraftKeyFromNewPost() async throws {
        // An edit must not coalesce with a new-post draft for the same community.
        let db = try AppDatabase.inMemory()
        let accountId = try await OutboundContentMigrationTests.seedAccount(db)
        let newPostToken = try await db.upsertOutboundDraft(makeCreateInput(), accountId: accountId, now: 0)
        let editToken = try await db.upsertOutboundDraft(makeEditInput(serverPostId: 5), accountId: accountId, now: 0)
        #expect(newPostToken != editToken)
        let rows = try await db.allOutbound(accountId: accountId)
        #expect(rows.count == 2)
        let editRow = rows.first { $0.editPostServerId == 5 }
        #expect(editRow?.draftKey == "ep:5")
        let newPostRow = rows.first { $0.editPostServerId == nil }
        #expect(newPostRow?.draftKey == "p:1")
    }

    // MARK: - Performer / drain

    @Test
    func editDrainsByCallingPerformerWithEditTarget() async throws {
        let db = try AppDatabase.inMemory()
        let accountId = try await OutboundContentMigrationTests.seedAccount(db)
        let performer = RecordingPerformer(result: 42)
        let svc = ComposerOutboxService(
            accountId: accountId,
            appDatabase: db,
            performer: performer,
            reachability: FakeReachability(),
            now: { 0 }
        )
        let successes = await svc.successEvents
        let token = try await db.upsertOutboundDraft(makeEditInput(serverPostId: 42), accountId: accountId, now: 0)
        try await db.markOutboundQueued(clientToken: token, now: 0)
        await svc.drainOnce()

        // The performer saw exactly the edit record, carrying the edit target.
        #expect(await performer.calls == 1)
        let performed = await performer.performedRecords
        #expect(performed.first?.editPostServerId == 42)
        #expect(performed.first?.kind == OutboundKind.post.rawValue)
        #expect(performed.first?.title == "Edited title")
        #expect(performed.first?.body == "Edited body")
        // Success deletes the outbound row and emits success.
        #expect(try await db.allOutbound(accountId: accountId).isEmpty)
        var it = successes.makeAsyncIterator()
        #expect(await it.next()?.clientToken == token)
    }

    @Test
    func editPermanentFailureParksAsFailedKeepingContent() async throws {
        let db = try AppDatabase.inMemory()
        let accountId = try await OutboundContentMigrationTests.seedAccount(db)
        // A performer that throws a permanent error.
        let performer = ThrowingPerformer(error: LemmyServiceError.requiresAuthentication)
        let svc = ComposerOutboxService(
            accountId: accountId,
            appDatabase: db,
            performer: performer,
            reachability: FakeReachability(),
            now: { 0 }
        )
        let token = try await db.upsertOutboundDraft(makeEditInput(serverPostId: 9), accountId: accountId, now: 0)
        try await db.markOutboundQueued(clientToken: token, now: 0)
        await svc.drainOnce()
        let rows = try await db.allOutbound(accountId: accountId)
        // Parked as failed (content kept), exactly like a failed new post.
        #expect(rows.count == 1)
        #expect(rows.first?.status == OutboundStatus.failed.rawValue)
        #expect(rows.first?.editPostServerId == 9)
        #expect(rows.first?.title == "Edited title")
        #expect(rows.first?.body == "Edited body")
    }

    @Test
    func dedupSkippedForPostEdits() async throws {
        // The create-dedup is comment-only and additionally gated on
        // `editPostServerId == nil`. A post edit must always reach the performer.
        let db = try AppDatabase.inMemory()
        let accountId = try await OutboundContentMigrationTests.seedAccount(db)
        let performer = RecordingPerformer(result: 3)
        let svc = ComposerOutboxService(
            accountId: accountId,
            appDatabase: db,
            performer: performer,
            reachability: FakeReachability(),
            now: { 0 }
        )
        let token = try await db.upsertOutboundDraft(makeEditInput(serverPostId: 3), accountId: accountId, now: 0)
        try await db.markOutboundQueued(clientToken: token, now: 0)
        await svc.drainOnce()
        #expect(await performer.calls == 1)
        #expect(try await db.allOutbound(accountId: accountId).isEmpty)
    }

    // MARK: - hasPendingOutboundPostEdit helper

    @Test
    func hasPendingOutboundPostEditTracksSendingAndFailed() async throws {
        let db = try AppDatabase.inMemory()
        let accountId = try await OutboundContentMigrationTests.seedAccount(db)
        let token = try await db.upsertOutboundDraft(makeEditInput(serverPostId: 11), accountId: accountId, now: 0)

        // Draft: not yet pending.
        var pending = try await db.writer.read { db in
            try AppDatabase.hasPendingOutboundPostEdit(db, accountId: accountId, serverPostId: 11)
        }
        #expect(pending == false)

        // Queued: still excluded (the drain's successful upsert bypasses the guard).
        try await db.markOutboundQueued(clientToken: token, now: 0)
        pending = try await db.writer.read { db in
            try AppDatabase.hasPendingOutboundPostEdit(db, accountId: accountId, serverPostId: 11)
        }
        #expect(pending == false)

        // Sending: pending.
        let rowId = try await db.writer.read { db in
            try OutboundContentRecord.filter(Column("clientToken") == token).fetchOne(db)?.id
        }
        try await db.markOutboundSending(id: #require(rowId), now: 0)
        pending = try await db.writer.read { db in
            try AppDatabase.hasPendingOutboundPostEdit(db, accountId: accountId, serverPostId: 11)
        }
        #expect(pending == true)

        // Failed: pending.
        try await db.markOutboundFailed(id: #require(rowId), lastError: "x", now: 0)
        pending = try await db.writer.read { db in
            try AppDatabase.hasPendingOutboundPostEdit(db, accountId: accountId, serverPostId: 11)
        }
        #expect(pending == true)
    }
}

/// A performer that always throws the given error (used to exercise the
/// permanent-failure park path for post edits).
private actor ThrowingPerformer: OutboundContentPerforming {
    private let error: any Error
    init(error: any Error) {
        self.error = error
    }

    func perform(_: OutboundContentRecord) async throws -> Int64? {
        throw error
    }
}
