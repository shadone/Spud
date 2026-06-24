//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
@testable import SpudDataKit

struct OutboundContentWritesTests {
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
    func upsertDraft_insertsThenUpdatesSameRow() async throws {
        let db = try AppDatabase.inMemory()
        let acc = try await OutboundContentMigrationTests.seedAccount(db)
        let token1 = try await db.upsertOutboundDraft(makeInput(), accountId: acc, now: 100)
        var updated = makeInput()
        updated.body = "edited"
        let token2 = try await db.upsertOutboundDraft(updated, accountId: acc, now: 200)
        #expect(token1 == token2) // same draft row reused per draftKey
        let loaded = try await db.loadOutboundDraft(accountId: acc, draftKey: "c:1:0")
        #expect(loaded?.body == "edited")
        #expect(loaded?.updatedAt == 200)
    }

    @Test
    func submitTransitionsDraftToQueued_thenDueIncludesIt() async throws {
        let db = try AppDatabase.inMemory()
        let acc = try await OutboundContentMigrationTests.seedAccount(db)
        let token = try await db.upsertOutboundDraft(makeInput(), accountId: acc, now: 0)
        try await db.markOutboundQueued(clientToken: token, now: 50)
        let due = try await db.dueOutbound(accountId: acc, asOf: 50)
        #expect(due.count == 1)
        #expect(due.first?.status == OutboundStatus.queued.rawValue)
        #expect(due.first?.nextAttemptAt == 50)
    }

    @Test
    func retrying_setsBackoff_notDueUntilTime() async throws {
        let db = try AppDatabase.inMemory()
        let acc = try await OutboundContentMigrationTests.seedAccount(db)
        let token = try await db.upsertOutboundDraft(makeInput(), accountId: acc, now: 0)
        try await db.markOutboundQueued(clientToken: token, now: 0)
        let id = try try await #require(db.dueOutbound(accountId: acc, asOf: 0).first?.id)
        try await db.markOutboundRetrying(id: id, lastError: "net", nextAttemptAt: 100, now: 10)
        #expect(try await db.dueOutbound(accountId: acc, asOf: 50).isEmpty) // backoff not elapsed
        #expect(try await db.dueOutbound(accountId: acc, asOf: 100).count == 1) // now due
    }

    @Test
    func failed_isNotAutoDrained_butShowsInAll() async throws {
        let db = try AppDatabase.inMemory()
        let acc = try await OutboundContentMigrationTests.seedAccount(db)
        let token = try await db.upsertOutboundDraft(makeInput(), accountId: acc, now: 0)
        try await db.markOutboundQueued(clientToken: token, now: 0)
        let id = try try await #require(db.dueOutbound(accountId: acc, asOf: 0).first?.id)
        try await db.markOutboundFailed(id: id, lastError: "403", now: 10)
        #expect(try await db.dueOutbound(accountId: acc, asOf: .greatestFiniteMagnitude).isEmpty)
        #expect(try await db.allOutbound(accountId: acc).count == 1)
    }

    @Test
    func delete_removesRow() async throws {
        let db = try AppDatabase.inMemory()
        let acc = try await OutboundContentMigrationTests.seedAccount(db)
        let token = try await db.upsertOutboundDraft(makeInput(), accountId: acc, now: 0)
        try await db.deleteOutbound(clientToken: token)
        #expect(try await db.allOutbound(accountId: acc).isEmpty)
    }
}
