//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

/// A persisted private (direct) message.
///
/// Mirrors one Lemmy `PrivateMessage`, scoped to the signed-in account so the
/// same server message id can coexist across accounts. The two participants
/// are referenced by their **server** person ids (`creatorServerPersonId` /
/// `recipientServerPersonId`), not by `person` row ids: the read layer joins to
/// the `person` table on `(siteId, personId)` for name/avatar, the same way the
/// other records reference people. The "correspondent" (the participant who is
/// not the account holder) is a derived notion computed only in the read layer
/// — it is never stored here.
public struct PrivateMessageRecord: Codable, Sendable, Equatable, Identifiable {
    public static let databaseTableName = "privateMessage"

    public var id: Int64?
    /// Scopes the message to the signed-in account; cascades on account delete.
    public var accountId: Int64
    /// The Lemmy `PrivateMessageID`. Unique per `accountId` (see the
    /// `(accountId, serverMessageId)` unique index in migration `v23`).
    public var serverMessageId: Int64
    /// Server person id of the message author.
    public var creatorServerPersonId: Int64
    /// Server person id of the message recipient.
    public var recipientServerPersonId: Int64
    public var content: String
    public var published: Date
    /// Whether the message has been read. Carried by the Lemmy object and
    /// refreshed in place on re-import.
    public var isRead: Bool
    /// Whether the message was deleted (by its author). Mirrored from the Lemmy
    /// object; kept so a later slice can fold deleted messages out of a thread.
    public var isDeleted: Bool
    public var updatedAt: Date

    public init(
        id: Int64? = nil,
        accountId: Int64,
        serverMessageId: Int64,
        creatorServerPersonId: Int64,
        recipientServerPersonId: Int64,
        content: String,
        published: Date,
        isRead: Bool = false,
        isDeleted: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.accountId = accountId
        self.serverMessageId = serverMessageId
        self.creatorServerPersonId = creatorServerPersonId
        self.recipientServerPersonId = recipientServerPersonId
        self.content = content
        self.published = published
        self.isRead = isRead
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}

extension PrivateMessageRecord: FetchableRecord, MutablePersistableRecord {
    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
