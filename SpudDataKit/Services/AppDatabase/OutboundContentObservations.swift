//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import OSLog

private let logger = Logger.appDatabase

public extension AppDatabase {
    /// Outbound comment rows for `postServerId` belonging to `accountKeychainId`,
    /// in creation order. Backs the post-detail overlay of pending/failed
    /// comments. A successful send deletes the row (there is no `sent` status),
    /// so the overlay node vanishes once the real comment lands.
    func observeOutboundComments(
        postServerId: Int64,
        accountKeychainId: String
    ) -> AsyncStream<[OutboundContentRecord]> {
        let observation = ValueObservation
            .tracking { db -> [OutboundContentRecord] in
                try OutboundContentRecord
                    .filter(Column("kind") == OutboundKind.comment.rawValue)
                    .filter(Column("postServerId") == postServerId)
                    .filter(sql: "accountId IN (SELECT id FROM account WHERE accountKeychainId = ?)", arguments: [accountKeychainId])
                    .order(Column("createdAt").asc)
                    .fetchAll(db)
            }
            .removeDuplicates()

        return AsyncStream { continuation in
            let cancellable = observation.start(in: writer, scheduling: .async(onQueue: .global(qos: .userInitiated))) { error in
                logger.error("observeOutboundComments failed: \(String(describing: error), privacy: .public)")
                continuation.finish()
            } onChange: { value in
                continuation.yield(value)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    /// Outbound direct-message SEND rows to `recipientServerPersonId` belonging to
    /// `accountKeychainId`, in creation order. Backs the DM thread's overlay of
    /// pending/failed (and the brief sending state of) outgoing messages. A
    /// successful send deletes the row (there is no `sent` status) once the
    /// confirmed message lands in the persistent `privateMessage` store, so the
    /// optimistic bubble is replaced by the real one. Several in-flight sends to
    /// the same recipient each surface as their own row (unique `dmSendKey`).
    ///
    /// The per-recipient autosave DRAFT row (status `draft`) shares this kind +
    /// recipient but is explicitly excluded: it is unsent compose-bar text, not an
    /// in-flight message, and would otherwise render as a phantom "Sending…" bubble
    /// on every keystroke. Only queued/sending/failed SEND rows flow through.
    func observeOutboundDMs(
        recipientServerPersonId: Int64,
        accountKeychainId: String
    ) -> AsyncStream<[OutboundContentRecord]> {
        let observation = ValueObservation
            .tracking { db -> [OutboundContentRecord] in
                try OutboundContentRecord
                    .filter(Column("kind") == OutboundKind.directMessage.rawValue)
                    .filter(Column("recipientServerPersonId") == recipientServerPersonId)
                    .filter(Column("status") != OutboundStatus.draft.rawValue)
                    .filter(sql: "accountId IN (SELECT id FROM account WHERE accountKeychainId = ?)", arguments: [accountKeychainId])
                    .order(Column("createdAt").asc)
                    .fetchAll(db)
            }
            .removeDuplicates()

        return AsyncStream { continuation in
            let cancellable = observation.start(in: writer, scheduling: .async(onQueue: .global(qos: .userInitiated))) { error in
                logger.error("observeOutboundDMs failed: \(String(describing: error), privacy: .public)")
                continuation.finish()
            } onChange: { value in
                continuation.yield(value)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    /// Outbound direct-message SEND rows across ALL recipients for
    /// `accountKeychainId`, in creation order. The all-recipients sibling of
    /// `observeOutboundDMs` — it backs the inbox CONVERSATION LIST (not a single
    /// thread), so the list can show a per-conversation "Sending…" / "Not
    /// delivered" indicator and surface a brand-new conversation optimistically
    /// (a first message to someone with no persisted server messages yet).
    ///
    /// Same row semantics as the per-recipient variant: a successful send deletes
    /// the row (no `sent` status) once the confirmed message lands in the
    /// `privateMessage` store.
    ///
    /// The only status filter is `status != draft`, so this returns ALL non-draft
    /// SEND states — `queued`, `sending`, AND `failed` — not just sending/failed.
    /// Including `queued` is intentional: a queued send is in-flight (it just
    /// hasn't started its network attempt yet) and must drive the row's "Sending…"
    /// indicator, so the optimistic row appears the instant the send is enqueued.
    /// The per-recipient autosave DRAFT row (status `draft`) is the sole exclusion
    /// — it is unsent compose-bar text, not an in-flight message, and must never
    /// inflate a conversation row.
    func observeOutboundDirectMessages(accountKeychainId: String) -> AsyncStream<[OutboundContentRecord]> {
        let observation = ValueObservation
            .tracking { db -> [OutboundContentRecord] in
                try OutboundContentRecord
                    .filter(Column("kind") == OutboundKind.directMessage.rawValue)
                    .filter(Column("status") != OutboundStatus.draft.rawValue)
                    .filter(sql: "accountId IN (SELECT id FROM account WHERE accountKeychainId = ?)", arguments: [accountKeychainId])
                    .order(Column("createdAt").asc)
                    .fetchAll(db)
            }
            .removeDuplicates()

        return AsyncStream { continuation in
            let cancellable = observation.start(in: writer, scheduling: .async(onQueue: .global(qos: .userInitiated))) { error in
                logger.error("observeOutboundDirectMessages failed: \(String(describing: error), privacy: .public)")
                continuation.finish()
            } onChange: { value in
                continuation.yield(value)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    /// All outbound rows for `accountKeychainId`, newest first. Backs the Drafts
    /// & Outbox list.
    func observeOutboundContent(accountKeychainId: String) -> AsyncStream<[OutboundContentRecord]> {
        let observation = ValueObservation
            .tracking { db -> [OutboundContentRecord] in
                try OutboundContentRecord
                    .filter(sql: "accountId IN (SELECT id FROM account WHERE accountKeychainId = ?)", arguments: [accountKeychainId])
                    .order(Column("createdAt").desc)
                    .fetchAll(db)
            }
            .removeDuplicates()

        return AsyncStream { continuation in
            let cancellable = observation.start(in: writer, scheduling: .async(onQueue: .global(qos: .userInitiated))) { error in
                logger.error("observeOutboundContent failed: \(String(describing: error), privacy: .public)")
                continuation.finish()
            } onChange: { value in
                continuation.yield(value)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }
}
