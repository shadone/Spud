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
