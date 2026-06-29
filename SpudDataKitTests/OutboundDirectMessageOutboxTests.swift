//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import Testing
@testable import SpudDataKit

/// A performer that records the records it was handed and always succeeds.
/// Lets the queue-mechanics tests below exercise enqueue/observe/draft behavior
/// without a network stub (the full createPrivateMessage path is covered by
/// `OutboundDirectMessagePerformerTests`).
private actor RecordingPerformer: OutboundContentPerforming {
    private(set) var performedRecords: [OutboundContentRecord] = []

    func perform(_ record: OutboundContentRecord) async throws -> Int64? {
        performedRecords.append(record)
        return nil
    }
}

private final class FakeReachability: ReachabilityMonitoring, @unchecked Sendable {
    @MainActor var isOnline: Bool = true
    @MainActor var statusStream: AsyncStream<Bool> {
        AsyncStream { $0.finish() }
    }
}

/// Service/queue-level coverage for the durable direct-message outbox kind:
/// the v24 migration column, the dual draft-key scheme (per-recipient autosave
/// draft vs. unique per-send key), multiple coexisting in-flight sends, and the
/// `observeOutboundDMs` stream.
struct OutboundDirectMessageOutboxTests {
    private enum PID {
        static let alice: Int64 = 200
        static let bob: Int64 = 300
    }

    // MARK: - Migration

    @Test
    func recipientColumnExistsAfterV24() async throws {
        let db = try AppDatabase.inMemory()
        let columns = try await db.writer.read { db in
            try db.columns(in: "outboundContent").map(\.name)
        }
        #expect(columns.contains("recipientServerPersonId"))
    }

    // MARK: - Draft-key scheme

    @Test
    func dmDraftKeyIsPerRecipientSingleton() async throws {
        let db = try AppDatabase.inMemory()
        let acc = try await OutboundContentMigrationTests.seedAccount(db)

        // First autosave for alice.
        let token1 = try await db.saveDirectMessageDraftInput(body: "hi", recipient: PID.alice, accountId: acc)
        // Re-save (e.g. the user kept typing): same draft row, in place.
        let token2 = try await db.saveDirectMessageDraftInput(body: "hi there", recipient: PID.alice, accountId: acc)
        #expect(token1 == token2)

        let drafts = try await db.allOutbound(accountId: acc)
            .filter { $0.kind == OutboundKind.directMessage.rawValue && $0.status == OutboundStatus.draft.rawValue }
        // Exactly one draft row per correspondent, updated in place.
        #expect(drafts.count == 1)
        #expect(drafts.first?.draftKey == "dm:\(PID.alice)")
        #expect(drafts.first?.body == "hi there")
        #expect(drafts.first?.recipientServerPersonId == PID.alice)
    }

    @Test
    func dmSendKeyIsUniquePerSend() {
        // Two sends to the same recipient yield distinct keys (salted by token),
        // so they never collide on the (accountId, draftKey) draft unique index.
        let a = OutboundContentRecord.dmSendKey(recipientServerPersonId: PID.alice, clientToken: "t1")
        let b = OutboundContentRecord.dmSendKey(recipientServerPersonId: PID.alice, clientToken: "t2")
        #expect(a == "dm:\(PID.alice):send:t1")
        #expect(b == "dm:\(PID.alice):send:t2")
        #expect(a != b)
        // The send key is also distinct from the autosave draft key.
        #expect(a != OutboundContentRecord.dmDraftKey(recipientServerPersonId: PID.alice))
    }

    // MARK: - Multiple in-flight sends to the same recipient

    @Test
    func multipleSendsToSameRecipientCoexist() async throws {
        let db = try AppDatabase.inMemory()
        let acc = try await OutboundContentMigrationTests.seedAccount(db)

        // Two queued sends to the SAME recipient — no unique-index collision.
        let t1 = try await db.enqueueOutboundDirectMessage(
            body: "first", recipientServerPersonId: PID.alice, accountId: acc, now: 0
        )
        let t2 = try await db.enqueueOutboundDirectMessage(
            body: "second", recipientServerPersonId: PID.alice, accountId: acc, now: 1
        )
        #expect(t1 != t2)

        let rows = try await db.allOutbound(accountId: acc)
            .filter { $0.kind == OutboundKind.directMessage.rawValue }
        #expect(rows.count == 2)
        // Both are queued, both target alice, distinct unique keys.
        #expect(rows.allSatisfy { $0.status == OutboundStatus.queued.rawValue })
        #expect(rows.allSatisfy { $0.recipientServerPersonId == PID.alice })
        #expect(Set(rows.map(\.draftKey)).count == 2)
    }

    // MARK: - observeOutboundDMs

    @Test
    func observeOutboundDMsFiltersByRecipientInOrder() async throws {
        let db = try AppDatabase.inMemory()
        let acc = try await OutboundContentMigrationTests.seedAccount(db)
        let keychainId = try await db.writer.read { db in
            try String.fetchOne(db, sql: "SELECT accountKeychainId FROM account WHERE id = ?", arguments: [acc])
        }
        let kc = try #require(keychainId)

        // Two sends to alice (older then newer) and one to bob.
        _ = try await db.enqueueOutboundDirectMessage(body: "alice 1", recipientServerPersonId: PID.alice, accountId: acc, now: 0)
        _ = try await db.enqueueOutboundDirectMessage(body: "alice 2", recipientServerPersonId: PID.alice, accountId: acc, now: 10)
        _ = try await db.enqueueOutboundDirectMessage(body: "bob 1", recipientServerPersonId: PID.bob, accountId: acc, now: 5)

        let aliceRows = await Self.first(db.observeOutboundDMs(recipientServerPersonId: PID.alice, accountKeychainId: kc))
        // Only alice's sends, oldest-first.
        #expect(aliceRows.map(\.body) == ["alice 1", "alice 2"])
        #expect(aliceRows.allSatisfy { $0.recipientServerPersonId == PID.alice })

        let bobRows = await Self.first(db.observeOutboundDMs(recipientServerPersonId: PID.bob, accountKeychainId: kc))
        #expect(bobRows.map(\.body) == ["bob 1"])
    }

    @Test
    func observeOutboundDMsExcludesCommentsAndPosts() async throws {
        let db = try AppDatabase.inMemory()
        let acc = try await OutboundContentMigrationTests.seedAccount(db)
        let kc = try #require(try await db.writer.read { db in
            try String.fetchOne(db, sql: "SELECT accountKeychainId FROM account WHERE id = ?", arguments: [acc])
        })

        // A comment draft and a DM send to alice.
        _ = try await db.upsertOutboundDraft(
            OutboundDraftInput(
                kind: .comment, body: "a comment", postServerId: 1, parentCommentServerId: nil,
                communityServerId: nil, title: nil, url: nil, nsfw: false, postType: 0
            ),
            accountId: acc, now: 0
        )
        _ = try await db.enqueueOutboundDirectMessage(body: "a dm", recipientServerPersonId: PID.alice, accountId: acc, now: 1)

        let rows = await Self.first(db.observeOutboundDMs(recipientServerPersonId: PID.alice, accountKeychainId: kc))
        // The comment must not leak into the DM stream.
        #expect(rows.map(\.body) == ["a dm"])
    }

    // MARK: - Drain delegation

    @Test
    func drainHandsDirectMessageRowToPerformer() async throws {
        let db = try AppDatabase.inMemory()
        let acc = try await OutboundContentMigrationTests.seedAccount(db)
        let performer = RecordingPerformer()
        let svc = ComposerOutboxService(
            accountId: acc, appDatabase: db, performer: performer,
            reachability: FakeReachability(), now: { 0 }
        )

        _ = try await db.enqueueOutboundDirectMessage(
            body: "drain me", recipientServerPersonId: PID.alice, accountId: acc, now: 0
        )
        await svc.drainOnce()

        let performed = await performer.performedRecords
        #expect(performed.count == 1)
        #expect(performed.first?.kind == OutboundKind.directMessage.rawValue)
        #expect(performed.first?.recipientServerPersonId == PID.alice)
        #expect(performed.first?.body == "drain me")
        // Success deletes the row.
        #expect(try await db.allOutbound(accountId: acc).isEmpty)
    }

    // MARK: - Helpers

    private static func first(_ stream: AsyncStream<[OutboundContentRecord]>) async -> [OutboundContentRecord] {
        for await rows in stream {
            return rows
        }
        return []
    }
}

private extension AppDatabase {
    /// Test convenience: upsert a DM autosave draft via the same input path the
    /// service uses, returning the clientToken.
    func saveDirectMessageDraftInput(body: String, recipient: Int64, accountId: Int64) async throws -> String {
        try await upsertOutboundDraft(
            OutboundDraftInput(
                kind: .directMessage, body: body, postServerId: nil, parentCommentServerId: nil,
                communityServerId: nil, title: nil, url: nil, nsfw: false, postType: 0,
                recipientServerPersonId: recipient
            ),
            accountId: accountId, now: 0
        )
    }
}
