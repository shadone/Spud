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
    /// Deletes feed rows - and their pages / pageElements - older than `age`.
    /// Feeds are addressed only by their session-minted UUID feedKey, and no
    /// feedKey is ever persisted across launches, so any feed older than a short
    /// margin is an unreachable orphan. Children are deleted explicitly because
    /// PRAGMA foreign_keys is a no-op inside GRDB's write transaction and is not
    /// guaranteed on pool connections, so ON DELETE CASCADE cannot be relied on
    /// here. Shared post/community/person rows are intentionally left intact.
    /// Returns the number of feed rows deleted.
    @discardableResult
    func pruneStaleFeedRows(olderThan age: TimeInterval = 300) async throws -> Int {
        let cutoff = Date().addingTimeInterval(-age)
        let deleted = try await writer.write { db in
            try db.execute(
                sql: """
                    DELETE FROM pageElement
                    WHERE pageId IN (
                        SELECT page.id FROM page
                        JOIN feed ON feed.id = page.feedId
                        WHERE feed.createdAt < ?
                    )
                    """,
                arguments: [cutoff]
            )
            try db.execute(
                sql: """
                    DELETE FROM page
                    WHERE feedId IN (SELECT id FROM feed WHERE createdAt < ?)
                    """,
                arguments: [cutoff]
            )
            return try FeedRecord
                .filter(Column("createdAt") < cutoff)
                .deleteAll(db)
        }
        if deleted > 0 {
            logger.debug("pruneStaleFeedRows: deleted \(deleted, privacy: .public) stale feed rows")
        }
        return deleted
    }
}
