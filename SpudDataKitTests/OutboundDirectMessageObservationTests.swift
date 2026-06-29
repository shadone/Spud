//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import Testing
@testable import SpudDataKit

/// Coverage for `observeOutboundDirectMessages` — the all-recipients sibling of
/// `observeOutboundDMs` that backs the inbox conversation LIST. Asserts it
/// surfaces outbound DM SEND rows across every recipient for the account, with
/// the per-recipient autosave DRAFT excluded.
struct OutboundDirectMessageObservationTests {
    private enum PID {
        static let alice: Int64 = 200
        static let bob: Int64 = 300
    }

    private static func insertDM(
        _ db: Database,
        accountId: Int64,
        recipient: Int64,
        body: String,
        status: OutboundStatus,
        clientToken: String,
        createdAt: Double
    ) throws {
        let draftKey = status == .draft
            ? OutboundContentRecord.dmDraftKey(recipientServerPersonId: recipient)
            : OutboundContentRecord.dmSendKey(recipientServerPersonId: recipient, clientToken: clientToken)
        var row = OutboundContentRecord(
            id: nil,
            clientToken: clientToken,
            accountId: accountId,
            kind: OutboundKind.directMessage.rawValue,
            status: status.rawValue,
            draftKey: draftKey,
            body: body,
            postServerId: nil,
            parentCommentServerId: nil,
            communityServerId: nil,
            title: nil,
            url: nil,
            nsfw: false,
            postType: 0,
            editCommentServerId: nil,
            editPostServerId: nil,
            recipientServerPersonId: recipient,
            attempts: 0,
            lastError: nil,
            nextAttemptAt: nil,
            createdAt: createdAt,
            updatedAt: createdAt
        )
        try row.insert(db)
    }

    private static func first(_ stream: AsyncStream<[OutboundContentRecord]>) async -> [OutboundContentRecord] {
        for await rows in stream {
            return rows
        }
        return []
    }

    @Test
    func returnsSendsAcrossRecipients_inCreationOrder_draftExcluded() async throws {
        let db = try AppDatabase.inMemory()
        let acc = try await OutboundContentMigrationTests.seedAccount(db)

        try await db.writer.write { write in
            // A failed send to Alice and a sending one to Bob (two recipients).
            try Self.insertDM(write, accountId: acc, recipient: PID.alice, body: "to alice", status: .failed, clientToken: "t-alice", createdAt: 100)
            try Self.insertDM(write, accountId: acc, recipient: PID.bob, body: "to bob", status: .sending, clientToken: "t-bob", createdAt: 200)
            // An autosave DRAFT to Alice — must NOT surface (it's unsent text).
            try Self.insertDM(write, accountId: acc, recipient: PID.alice, body: "draft text", status: .draft, clientToken: "t-alice-draft", createdAt: 300)
        }

        let rows = await Self.first(db.observeOutboundDirectMessages(accountKeychainId: "test@example.com"))

        // Both sends across the two recipients, in creation order; the draft is gone.
        #expect(rows.count == 2)
        #expect(rows.map(\.clientToken) == ["t-alice", "t-bob"])
        #expect(rows.allSatisfy { $0.status != OutboundStatus.draft.rawValue })
        #expect(Set(rows.compactMap(\.recipientServerPersonId)) == [PID.alice, PID.bob])
    }

    @Test
    func excludesNonDirectMessageKinds() async throws {
        let db = try AppDatabase.inMemory()
        let acc = try await OutboundContentMigrationTests.seedAccount(db)

        try await db.writer.write { write in
            // A comment send must not leak into the DM observation.
            var comment = OutboundContentRecord(
                id: nil, clientToken: "c-1", accountId: acc, kind: OutboundKind.comment.rawValue,
                status: OutboundStatus.sending.rawValue, draftKey: "c:1:0", body: "a comment",
                postServerId: 1, parentCommentServerId: nil, communityServerId: nil, title: nil,
                url: nil, nsfw: false, postType: 0, editCommentServerId: nil, editPostServerId: nil,
                recipientServerPersonId: nil, attempts: 0, lastError: nil, nextAttemptAt: nil,
                createdAt: 10, updatedAt: 10
            )
            try comment.insert(write)
            try Self.insertDM(write, accountId: acc, recipient: PID.alice, body: "to alice", status: .sending, clientToken: "t-alice", createdAt: 20)
        }

        let rows = await Self.first(db.observeOutboundDirectMessages(accountKeychainId: "test@example.com"))
        #expect(rows.map(\.clientToken) == ["t-alice"])
    }
}
