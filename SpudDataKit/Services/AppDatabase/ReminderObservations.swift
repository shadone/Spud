//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import OSLog

private let logger = Logger.appDatabase

/// One row of the Inbox "Reminders" segment. A denormalized read-model over
/// `ReminderRecord` - `apId`/`titleSnapshot`/`communityName`/`instanceHost`/
/// `thumbnailUrl` are copied straight from the record (already denormalized at
/// write time), so the segment renders and opens a reminder without touching
/// the (possibly evicted) `post` cache row.
public struct ReminderListRow: Sendable, Equatable, Hashable, Identifiable {
    public let id: Int64
    public let postServerId: Int64
    public let apId: String
    public let rootCommentServerId: Int64
    public let kind: String
    public let status: String
    public let unseen: Bool
    public let fireAt: Date?
    public let titleSnapshot: String
    public let communityName: String
    public let instanceHost: String
    public let thumbnailUrl: String?

    public init(
        id: Int64,
        postServerId: Int64,
        apId: String,
        rootCommentServerId: Int64,
        kind: String,
        status: String,
        unseen: Bool,
        fireAt: Date?,
        titleSnapshot: String,
        communityName: String,
        instanceHost: String,
        thumbnailUrl: String?
    ) {
        self.id = id
        self.postServerId = postServerId
        self.apId = apId
        self.rootCommentServerId = rootCommentServerId
        self.kind = kind
        self.status = status
        self.unseen = unseen
        self.fireAt = fireAt
        self.titleSnapshot = titleSnapshot
        self.communityName = communityName
        self.instanceHost = instanceHost
        self.thumbnailUrl = thumbnailUrl
    }
}

public extension AppDatabase {
    /// Live stream of the account's reminders for the Inbox "Reminders"
    /// segment, ordered fired-and-unseen first (newest badge items surface
    /// immediately), then everything else by `fireAt` ascending (soonest-due
    /// scheduled reminder next).
    func observeReminderList(accountId: Int64) -> AsyncStream<[ReminderListRow]> {
        let observation = ValueObservation
            .tracking { db -> [ReminderListRow] in
                let rows = try Row.fetchAll(db, sql: """
                        SELECT id, postServerId, apId, rootCommentServerId, kind, status, unseen,
                               fireAt, titleSnapshot, communityName, instanceHost, thumbnailUrl
                        FROM reminder
                        WHERE accountId = ?
                        ORDER BY
                            CASE WHEN status = ? AND unseen = 1 THEN 0 ELSE 1 END,
                            fireAt ASC
                    """, arguments: [accountId, ReminderRecord.Status.fired.rawValue])

                return rows.map { row in
                    ReminderListRow(
                        id: row["id"],
                        postServerId: row["postServerId"],
                        apId: row["apId"],
                        rootCommentServerId: row["rootCommentServerId"],
                        kind: row["kind"],
                        status: row["status"],
                        unseen: row["unseen"],
                        fireAt: row["fireAt"],
                        titleSnapshot: row["titleSnapshot"],
                        communityName: row["communityName"],
                        instanceHost: row["instanceHost"],
                        thumbnailUrl: row["thumbnailUrl"]
                    )
                }
            }
            .removeDuplicates()

        return AsyncStream { continuation in
            // ValueObservation.start defaults to .async(onQueue: .main), which is
            // @MainActor-isolated and illegal from this non-isolated AsyncStream
            // init closure. All *Observations.swift helpers in this project use
            // .async(onQueue: .global(qos: .userInitiated)) explicitly.
            let cancellable = observation.start(
                in: writer,
                scheduling: .async(onQueue: .global(qos: .userInitiated))
            ) { error in
                logger.error("observeReminderList ValueObservation failed: \(String(describing: error), privacy: .public)")
                continuation.finish()
            } onChange: { value in
                continuation.yield(value)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    /// Live stream of the fired-and-unseen reminder count for the account -
    /// backs the Inbox tab / segment badge (`unseenReminderCountSync` is the
    /// matching one-shot read).
    func observeUnseenReminderCount(accountId: Int64) -> AsyncStream<Int> {
        let observation = ValueObservation
            .tracking { db -> Int in
                try Int.fetchOne(db, sql: """
                        SELECT COUNT(*) FROM reminder WHERE accountId = ? AND status = ? AND unseen = 1
                    """, arguments: [accountId, ReminderRecord.Status.fired.rawValue]) ?? 0
            }
            .removeDuplicates()

        return AsyncStream { continuation in
            let cancellable = observation.start(
                in: writer,
                scheduling: .async(onQueue: .global(qos: .userInitiated))
            ) { error in
                logger.error("observeUnseenReminderCount ValueObservation failed: \(String(describing: error), privacy: .public)")
                continuation.finish()
            } onChange: { value in
                continuation.yield(value)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }
}
