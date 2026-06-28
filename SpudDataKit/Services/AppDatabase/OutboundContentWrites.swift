//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

public extension AppDatabase {
    /// Upsert the single draft row for `input`'s target. Returns its clientToken.
    func upsertOutboundDraft(_ input: OutboundDraftInput, accountId: Int64, now: Double) async throws -> String {
        try await writer.write { db in
            let key = OutboundContentRecord.draftKey(for: input)
            if var existing = try OutboundContentRecord
                .filter(Column("accountId") == accountId)
                .filter(Column("draftKey") == key)
                .filter(Column("status") == OutboundStatus.draft.rawValue)
                .fetchOne(db)
            {
                existing.body = input.body
                existing.title = input.title
                existing.url = input.url
                existing.nsfw = input.nsfw
                existing.postType = input.postType
                existing.postServerId = input.postServerId
                existing.parentCommentServerId = input.parentCommentServerId
                existing.communityServerId = input.communityServerId
                existing.editCommentServerId = input.editCommentServerId
                existing.updatedAt = now
                try existing.update(db)
                return existing.clientToken
            } else {
                let token = UUID().uuidString
                var row = OutboundContentRecord(
                    id: nil, clientToken: token, accountId: accountId, kind: input.kind.rawValue,
                    status: OutboundStatus.draft.rawValue, draftKey: key, body: input.body,
                    postServerId: input.postServerId, parentCommentServerId: input.parentCommentServerId,
                    communityServerId: input.communityServerId, title: input.title, url: input.url,
                    nsfw: input.nsfw, postType: input.postType,
                    editCommentServerId: input.editCommentServerId, attempts: 0, lastError: nil,
                    nextAttemptAt: nil, createdAt: now, updatedAt: now
                )
                try row.insert(db)
                return token
            }
        }
    }

    func loadOutboundDraft(accountId: Int64, draftKey: String) async throws -> OutboundContentRecord? {
        try await writer.read { db in
            try OutboundContentRecord
                .filter(Column("accountId") == accountId)
                .filter(Column("draftKey") == draftKey)
                .filter(Column("status") == OutboundStatus.draft.rawValue)
                .fetchOne(db)
        }
    }

    func markOutboundQueued(clientToken: String, now: Double) async throws {
        try await writer.write { db in
            try db.execute(
                sql: """
                    UPDATE outboundContent
                    SET status = ?, nextAttemptAt = ?, lastError = NULL, updatedAt = ?
                    WHERE clientToken = ?
                    """,
                arguments: [OutboundStatus.queued.rawValue, now, now, clientToken]
            )
        }
    }

    func markOutboundSending(id: Int64, now: Double) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "UPDATE outboundContent SET status = ?, updatedAt = ? WHERE id = ?",
                arguments: [OutboundStatus.sending.rawValue, now, id]
            )
        }
    }

    func markOutboundRetrying(id: Int64, lastError: String, nextAttemptAt: Double, now: Double) async throws {
        try await writer.write { db in
            try db.execute(
                sql: """
                    UPDATE outboundContent
                    SET status = ?, attempts = attempts + 1, lastError = ?, nextAttemptAt = ?, updatedAt = ?
                    WHERE id = ?
                    """,
                arguments: [OutboundStatus.queued.rawValue, lastError, nextAttemptAt, now, id]
            )
        }
    }

    func markOutboundFailed(id: Int64, lastError: String, now: Double) async throws {
        try await writer.write { db in
            try db.execute(
                sql: """
                    UPDATE outboundContent
                    SET status = ?, attempts = attempts + 1, lastError = ?, nextAttemptAt = NULL, updatedAt = ?
                    WHERE id = ?
                    """,
                arguments: [OutboundStatus.failed.rawValue, lastError, now, id]
            )
        }
    }

    func deleteOutbound(clientToken: String) async throws {
        try await writer.write { db in
            _ = try OutboundContentRecord
                .filter(Column("clientToken") == clientToken)
                .deleteAll(db)
        }
    }

    /// Rows eligible for an automatic send pass: queued/sending whose backoff has
    /// elapsed. `failed` rows are excluded (they wait for an explicit retry).
    func dueOutbound(accountId: Int64, asOf now: Double) async throws -> [OutboundContentRecord] {
        try await writer.read { db in
            try OutboundContentRecord
                .filter(Column("accountId") == accountId)
                .filter(
                    Column("status") == OutboundStatus.queued.rawValue ||
                        Column("status") == OutboundStatus.sending.rawValue
                )
                .filter(Column("nextAttemptAt") == nil || Column("nextAttemptAt") <= now)
                .order(Column("createdAt").asc)
                .fetchAll(db)
        }
    }

    func allOutbound(accountId: Int64) async throws -> [OutboundContentRecord] {
        try await writer.read { db in
            try OutboundContentRecord
                .filter(Column("accountId") == accountId)
                .order(Column("createdAt").asc)
                .fetchAll(db)
        }
    }

    /// True if a comment authored by `accountId`'s person already exists under the
    /// same post with the same trimmed body. Used to avoid double-sending when a
    /// prior attempt committed server-side but the response was lost.
    ///
    /// Note: the `comment` table stores Lemmy's materialized path string but has
    /// no direct parent-id column, so `parentCommentServerId` is accepted by the
    /// signature (for API compatibility) but is not matched — the check is
    /// (post + creator + trimmed body). A false positive from a duplicate body on
    /// the same post is far less damaging than a duplicate send.
    func matchingServerCommentExists(
        accountId: Int64, postServerId: Int64?, parentCommentServerId: Int64?, body: String
    ) async throws -> Bool {
        guard let postServerId else { return false }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return try await writer.read { db in
            // Resolve the account's person row id (comment.creatorId).
            // account.personId is nullable for signed-out accounts; return false when absent.
            let personRowId = try Int64.fetchOne(db, sql: """
                SELECT person.id FROM account
                JOIN person ON person.personId = account.personId
                          AND person.siteId = account.siteId
                WHERE account.id = ?
                """, arguments: [accountId])
            guard let personRowId else { return false }
            return try Bool.fetchOne(db, sql: """
                SELECT 1 FROM comment
                JOIN post ON post.id = comment.postId
                WHERE post.postId = ?
                  AND post.accountId = ?
                  AND comment.creatorId = ?
                  AND TRIM(comment.body) = ?
                LIMIT 1
                """, arguments: [postServerId, accountId, personRowId, trimmed]) ?? false
        }
    }
}
