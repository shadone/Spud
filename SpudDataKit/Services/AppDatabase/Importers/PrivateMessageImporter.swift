//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import LemmyKit
import OSLog

private let logger = Logger.appDatabase

/// A private-message view paired with its read state. The neutral
/// ``LemmyKit/PrivateMessage`` deliberately dropped v3's bare `read` bool (v4 moved
/// read state onto the unified notification entry), so the read flag rides
/// alongside the view here: the send path marks its own outgoing message read,
/// and the inbox fetch path sources it from `NotificationEntry.isRead`.
public struct IncomingPrivateMessage: Sendable {
    public let view: Lemmy.PrivateMessageView
    public let isRead: Bool

    public init(view: Lemmy.PrivateMessageView, isRead: Bool) {
        self.view = view
        self.isRead = isRead
    }
}

public extension AppDatabase {
    /// Public mirror entry point. Upserts a page of private-message views for
    /// `accountId` in its own write transaction.
    ///
    /// Resolves the account's `siteId` internally so the people referenced by
    /// the messages land on the right site (persons are keyed `(siteId,
    /// personId)`, same as post/comment creators). No-op — and logs — if the
    /// account row isn't in AppDatabase yet.
    func upsertPrivateMessages(
        _ messages: [IncomingPrivateMessage],
        accountId: Int64
    ) async throws {
        guard !messages.isEmpty else { return }
        try await writer.write { db in
            try Self.upsertPrivateMessages(messages, accountId: accountId, db: db)
        }
    }

    /// Upserts a page of private-message views for `accountId`. Caller must
    /// already be inside a write transaction.
    ///
    /// For each view this upserts both participants (creator + recipient) into
    /// the `person` table via the shared person-upsert path, then upserts the
    /// message row idempotently keyed on `(accountId, serverMessageId)`: a
    /// re-import of the same server message updates it in place (including
    /// `isRead` / `isDeleted` / `content`) rather than inserting a duplicate.
    ///
    /// IMPORTANT — upsert only, never delete. A server page is partial (it's a
    /// window over the account's whole message history), so this importer must
    /// not remove rows that aren't in the page. Optimistic/pending sends are
    /// kept in a separate outbox table (a later slice) and merged at the read
    /// layer; reconciliation happens there, not by clearing this table.
    static func upsertPrivateMessages(
        _ messages: [IncomingPrivateMessage],
        accountId: Int64,
        db: Database
    ) throws {
        guard let siteId = try AccountRecord.fetchOne(db, key: accountId)?.siteId else {
            logger.debug("Skipping private-message mirror - account \(accountId, privacy: .public) not yet in AppDatabase")
            return
        }

        for message in messages {
            _ = try upsertPrivateMessage(from: message, accountId: accountId, siteId: siteId, db: db)
        }
    }

    /// Upserts a single private-message view (both participants + the message
    /// row). Returns the resolved message row id. Caller must already be inside
    /// a write transaction.
    @discardableResult
    static func upsertPrivateMessage(
        from incoming: IncomingPrivateMessage,
        accountId: Int64,
        siteId: Int64,
        db: Database
    ) throws -> Int64 {
        let view = incoming.view
        // Both participants are bare `Person` objects on the view; land them so
        // the read layer can join for name/avatar regardless of which one is the
        // correspondent.
        _ = try upsertPerson(from: view.creator, siteId: siteId, in: db)
        _ = try upsertPerson(from: view.recipient, siteId: siteId, in: db)

        let message = view.privateMessage
        let now = Date()
        let serverMessageId = Int64(message.id)

        if var existing = try PrivateMessageRecord
            .filter(Column("accountId") == accountId)
            .filter(Column("serverMessageId") == serverMessageId)
            .fetchOne(db)
        {
            existing.creatorServerPersonId = Int64(message.creatorId)
            existing.recipientServerPersonId = Int64(message.recipientId)
            existing.content = message.content
            existing.published = message.publishedAt
            existing.isRead = incoming.isRead
            existing.isDeleted = message.deleted
            existing.updatedAt = now
            try existing.update(db)
            return existing.id!
        }

        var record = PrivateMessageRecord(
            accountId: accountId,
            serverMessageId: serverMessageId,
            creatorServerPersonId: Int64(message.creatorId),
            recipientServerPersonId: Int64(message.recipientId),
            content: message.content,
            published: message.publishedAt,
            isRead: incoming.isRead,
            isDeleted: message.deleted,
            updatedAt: now
        )
        try record.insert(db)
        return record.id!
    }

    /// Set the `isRead` flag on a single persisted message in place, so the DM
    /// thread observation reflects the read state without waiting for the next
    /// server re-import.
    ///
    /// `markPrivateMessageAsRead` on the service only hits the server (Lemmy has
    /// no read state to refresh locally), so a GRDB-backed thread that wants the
    /// unread dot to clear immediately must write the flag here. No-op (and a
    /// silent return) when the message row isn't present for this account — the
    /// next full import will carry the canonical state anyway.
    func setPrivateMessageRead(
        accountId: Int64,
        serverMessageId: Int64,
        isRead: Bool
    ) async throws {
        try await writer.write { db in
            guard var record = try PrivateMessageRecord
                .filter(Column("accountId") == accountId)
                .filter(Column("serverMessageId") == serverMessageId)
                .fetchOne(db)
            else { return }
            guard record.isRead != isRead else { return }
            record.isRead = isRead
            record.updatedAt = Date()
            try record.update(db)
        }
    }

    /// One-shot synchronous read of the persisted messages for `accountId`,
    /// oldest first. Test/diagnostic helper mirroring the importer convention
    /// of providing a `*Sync` read.
    func privateMessagesSync(accountId: Int64) -> [PrivateMessageRecord] {
        (try? writer.read { db in
            try PrivateMessageRecord
                .filter(Column("accountId") == accountId)
                .order(Column("published").asc)
                .fetchAll(db)
        }) ?? []
    }
}
