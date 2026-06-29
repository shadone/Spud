//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import OSLog

private let logger = Logger.appDatabase

/// One row of the DM conversation list: the latest message exchanged with a
/// single correspondent (the participant who is not the account holder), plus
/// that thread's unread count.
///
/// Mirrors `InboxConversation` from the in-memory inbox grouping, but sourced
/// from the persisted `privateMessage` store rather than a live API page.
public struct PrivateMessageConversationRow: Sendable, Equatable, Identifiable {
    /// Server person id of the correspondent. Identifies the thread.
    public let correspondentServerPersonId: Int64
    /// Display name (falls back to the handle) of the correspondent, joined
    /// from the `person` table. nil if the person row isn't present yet.
    public let correspondentName: String?
    /// Avatar URL string of the correspondent, joined from the `person` table.
    public let correspondentAvatarUrl: String?
    /// Body of the most-recent message in the thread (preview text).
    public let latestContent: String
    /// Timestamp of the most-recent message; drives the newest-thread-first sort.
    public let latestPublished: Date
    /// Number of unread *incoming* messages — unread messages whose author is
    /// the correspondent (the inbox's incoming-only unread rule).
    public let unreadCount: Int

    public var id: Int64 {
        correspondentServerPersonId
    }

    public init(
        correspondentServerPersonId: Int64,
        correspondentName: String?,
        correspondentAvatarUrl: String?,
        latestContent: String,
        latestPublished: Date,
        unreadCount: Int
    ) {
        self.correspondentServerPersonId = correspondentServerPersonId
        self.correspondentName = correspondentName
        self.correspondentAvatarUrl = correspondentAvatarUrl
        self.latestContent = latestContent
        self.latestPublished = latestPublished
        self.unreadCount = unreadCount
    }
}

/// One message inside a DM thread, with its author's display name/avatar joined
/// from the `person` table. Render model for the chat-style DM thread.
public struct PrivateMessageRow: Sendable, Equatable, Identifiable {
    /// The Lemmy `PrivateMessageID`.
    public let serverMessageId: Int64
    /// Server person id of the author.
    public let creatorServerPersonId: Int64
    /// Server person id of the recipient.
    public let recipientServerPersonId: Int64
    /// Display name (falls back to the handle) of the author. nil if the
    /// person row isn't present yet.
    public let creatorName: String?
    /// Avatar URL string of the author.
    public let creatorAvatarUrl: String?
    public let content: String
    public let published: Date
    public let isRead: Bool
    public let isDeleted: Bool

    public var id: Int64 {
        serverMessageId
    }

    public init(
        serverMessageId: Int64,
        creatorServerPersonId: Int64,
        recipientServerPersonId: Int64,
        creatorName: String?,
        creatorAvatarUrl: String?,
        content: String,
        published: Date,
        isRead: Bool,
        isDeleted: Bool
    ) {
        self.serverMessageId = serverMessageId
        self.creatorServerPersonId = creatorServerPersonId
        self.recipientServerPersonId = recipientServerPersonId
        self.creatorName = creatorName
        self.creatorAvatarUrl = creatorAvatarUrl
        self.content = content
        self.published = published
        self.isRead = isRead
        self.isDeleted = isDeleted
    }
}

public extension AppDatabase {
    /// Stream of DM conversations for the account, one row per correspondent,
    /// newest-thread first.
    ///
    /// The "correspondent" is the participant who is not the account holder. We
    /// resolve the account's own person id from `account.personId`; when it is
    /// unknown (signed-out / not yet resolved) we fall back to treating the
    /// creator as the correspondent (received messages dominate the inbox, so the
    /// creator is almost always the other party). The correspondent is derived
    /// in SQL with a CASE expression so the grouping/aggregation stays a single
    /// query.
    ///
    /// "Unread" counts only unread *incoming* messages (creator == the
    /// correspondent), matching the in-memory inbox.
    func observeConversations(accountId: Int64) -> AsyncStream<[PrivateMessageConversationRow]> {
        let observation = ValueObservation
            .tracking { db -> [PrivateMessageConversationRow] in
                guard let account = try AccountRecord.fetchOne(db, key: accountId) else {
                    return []
                }
                let siteId = account.siteId
                // The account's own *server* person id. `account.personId` is a
                // person ROW id (FK to person.id), not the Lemmy PersonID, so we
                // resolve through the person table to get the server id the
                // message participant columns are keyed on. NULL (signed-out /
                // own person not yet imported) triggers the
                // creator-is-correspondent fallback below: the CASE can't match a
                // NULL, so every row lands on the ELSE branch (creator).
                let myServerPersonId: Int64? = try account.personId.flatMap { personRowId in
                    try PersonRecord.fetchOne(db, key: personRowId)?.personId
                }

                // correspondent = the participant who isn't me. With
                // myServerPersonId NULL the equality is never true, so every row
                // falls to ELSE (creator) — the creator-is-correspondent fallback.
                // Strategy: derive each message's correspondent in a `scoped`
                // subquery, group by it to find the per-thread max timestamp,
                // then re-join `scoped` to pull the latest message's content.
                // The latest-message join breaks `published` ties on
                // serverMessageId so a thread yields exactly one row even when
                // two messages share a timestamp.
                let sql = """
                    SELECT
                        grouped.correspondentServerPersonId AS correspondentServerPersonId,
                        person.displayName AS correspondentDisplayName,
                        person.name        AS correspondentName,
                        person.avatarUrl   AS correspondentAvatarUrl,
                        latest.content     AS latestContent,
                        latest.published   AS latestPublished,
                        (
                            SELECT COUNT(*)
                            FROM privateMessage unread
                            WHERE unread.accountId = ?
                              AND unread.isRead = 0
                              AND unread.creatorServerPersonId = grouped.correspondentServerPersonId
                        ) AS unreadCount
                    FROM (
                        SELECT
                            correspondentServerPersonId,
                            MAX(published) AS maxPublished
                        FROM (
                            SELECT
                                serverMessageId,
                                published,
                                CASE
                                    WHEN creatorServerPersonId = ? THEN recipientServerPersonId
                                    ELSE creatorServerPersonId
                                END AS correspondentServerPersonId
                            FROM privateMessage
                            WHERE accountId = ?
                        )
                        GROUP BY correspondentServerPersonId
                    ) AS grouped
                    JOIN (
                        SELECT
                            serverMessageId,
                            content,
                            published,
                            CASE
                                WHEN creatorServerPersonId = ? THEN recipientServerPersonId
                                ELSE creatorServerPersonId
                            END AS correspondentServerPersonId
                        FROM privateMessage
                        WHERE accountId = ?
                    ) AS latest
                        ON latest.correspondentServerPersonId = grouped.correspondentServerPersonId
                       AND latest.published = grouped.maxPublished
                       -- Tie-break: among messages sharing the max timestamp,
                       -- keep only the highest serverMessageId (one row/thread).
                       AND latest.serverMessageId = (
                           SELECT MAX(t.serverMessageId)
                           FROM privateMessage AS t
                           WHERE t.accountId = ?
                             AND t.published = grouped.maxPublished
                             AND (CASE
                                      WHEN t.creatorServerPersonId = ? THEN t.recipientServerPersonId
                                      ELSE t.creatorServerPersonId
                                  END) = grouped.correspondentServerPersonId
                       )
                    LEFT JOIN person
                        ON person.siteId = ?
                       AND person.personId = grouped.correspondentServerPersonId
                    ORDER BY grouped.maxPublished DESC, grouped.correspondentServerPersonId ASC
                    """

                // myServerPersonId NULL -> bind NULL; the equality never
                // matches, so the CASE lands on ELSE (creator) everywhere.
                let myPersonArg = myServerPersonId.map { $0 as any DatabaseValueConvertible }
                let rows = try Row.fetchAll(db, sql: sql, arguments: [
                    accountId, // unreadCount subquery
                    myPersonArg, accountId, // grouped (correspondent + account filter)
                    myPersonArg, accountId, // latest (correspondent + account filter)
                    accountId, myPersonArg, // tie-break subquery
                    siteId, // person join
                ])
                return rows.map { row in
                    PrivateMessageConversationRow(
                        correspondentServerPersonId: row["correspondentServerPersonId"],
                        // displayName falls back to the handle.
                        correspondentName: row.coalescingString("correspondentDisplayName", "correspondentName"),
                        correspondentAvatarUrl: row["correspondentAvatarUrl"],
                        latestContent: row["latestContent"] ?? "",
                        latestPublished: row["latestPublished"],
                        unreadCount: row["unreadCount"]
                    )
                }
            }
            .removeDuplicates()

        return AsyncStream { continuation in
            // Non-main scheduling: ValueObservation.start defaults to
            // .async(onQueue: .main), which is @MainActor-isolated and illegal
            // from this non-isolated AsyncStream init closure.
            let cancellable = observation.start(in: writer, scheduling: .async(onQueue: .global(qos: .userInitiated))) { error in
                logger.error("Conversation ValueObservation failed: \(String(describing: error), privacy: .public)")
                continuation.finish()
            } onChange: { value in
                continuation.yield(value)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    /// Stream of all messages exchanged with `correspondentServerPersonId` for
    /// the account, oldest first (thread order). Matches the messages array of
    /// `InboxConversation`. The author's name/avatar are joined from the
    /// `person` table on `(siteId, personId)`.
    func observeMessages(
        accountId: Int64,
        correspondentServerPersonId: Int64
    ) -> AsyncStream<[PrivateMessageRow]> {
        let observation = ValueObservation
            .tracking { db -> [PrivateMessageRow] in
                guard let siteId = try AccountRecord.fetchOne(db, key: accountId)?.siteId else {
                    return []
                }

                // A message belongs to this thread when the correspondent is
                // either participant (the account holder is the other one).
                let sql = """
                    SELECT
                        pm.serverMessageId         AS serverMessageId,
                        pm.creatorServerPersonId   AS creatorServerPersonId,
                        pm.recipientServerPersonId AS recipientServerPersonId,
                        creator.displayName        AS creatorDisplayName,
                        creator.name               AS creatorName,
                        creator.avatarUrl          AS creatorAvatarUrl,
                        pm.content                 AS content,
                        pm.published               AS published,
                        pm.isRead                  AS isRead,
                        pm.isDeleted               AS isDeleted
                    FROM privateMessage AS pm
                    LEFT JOIN person AS creator
                        ON creator.siteId = ?
                       AND creator.personId = pm.creatorServerPersonId
                    WHERE pm.accountId = ?
                      AND (pm.creatorServerPersonId = ? OR pm.recipientServerPersonId = ?)
                    ORDER BY pm.published ASC, pm.serverMessageId ASC
                    """

                let rows = try Row.fetchAll(db, sql: sql, arguments: [
                    siteId, accountId, correspondentServerPersonId, correspondentServerPersonId,
                ])
                return rows.map { row in
                    PrivateMessageRow(
                        serverMessageId: row["serverMessageId"],
                        creatorServerPersonId: row["creatorServerPersonId"],
                        recipientServerPersonId: row["recipientServerPersonId"],
                        creatorName: row.coalescingString("creatorDisplayName", "creatorName"),
                        creatorAvatarUrl: row["creatorAvatarUrl"],
                        content: row["content"] ?? "",
                        published: row["published"],
                        isRead: row["isRead"],
                        isDeleted: row["isDeleted"]
                    )
                }
            }
            .removeDuplicates()

        return AsyncStream { continuation in
            let cancellable = observation.start(in: writer, scheduling: .async(onQueue: .global(qos: .userInitiated))) { error in
                logger.error("Messages ValueObservation failed: \(String(describing: error), privacy: .public)")
                continuation.finish()
            } onChange: { value in
                continuation.yield(value)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }
}
