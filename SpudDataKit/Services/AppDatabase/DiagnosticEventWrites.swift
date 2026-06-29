//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

public extension AppDatabase {
    // MARK: - Insert

    /// Inserts a single diagnostic event into the `diagnosticEvent` table.
    ///
    /// The record's `id` is set by GRDB via `didInsert` after a successful write.
    /// The caller's copy is not mutated; the id is only visible on the copy held
    /// inside the write closure.
    func insertDiagnosticEvent(_ record: DiagnosticEventRecord) async throws {
        try await writer.write { db in
            var mutableRecord = record
            try mutableRecord.insert(db)
        }
    }

    // MARK: - Query

    /// Returns diagnostic events matching `filter`, ordered newest-first.
    ///
    /// - Parameter filter: Constrains category, minimum level, free-text search, and
    ///   row count.  See `DiagnosticLogFilter` for defaults.
    /// - Returns: Up to `filter.limit` rows, sorted by `timestamp DESC, id DESC`.
    ///
    /// A nil or empty `categories` set in `filter` imposes no category filter — all
    /// categories are returned.  Pass a non-empty set to restrict to specific categories.
    func recentDiagnosticEvents(_ filter: DiagnosticLogFilter) async throws -> [DiagnosticEventRecord] {
        try await writer.read { db in
            try Self.diagnosticEventQuery(filter: filter).fetchAll(db)
        }
    }

    // MARK: - Prune

    /// Removes stale diagnostic events to keep the table bounded.
    ///
    /// Two passes are run in a single write transaction:
    ///
    /// 1. **Age prune** — deletes all rows whose `timestamp < now - maxAgeSeconds`.
    /// 2. **Row-count prune** — deletes all rows except the newest `maxRows` (by
    ///    `timestamp DESC, id DESC`), ensuring the table never exceeds `maxRows`
    ///    regardless of insert rate.
    ///
    /// - Parameters:
    ///   - now: Current time as a Unix timestamp (seconds).  Injected for testability.
    ///   - maxRows: Maximum number of rows to retain.  Defaults to 10 000.
    ///   - maxAgeSeconds: Rows older than this many seconds are deleted.  Defaults to
    ///     14 days (14 × 24 × 3600).
    func pruneDiagnosticEvents(
        now: Double,
        maxRows: Int = 10000,
        maxAgeSeconds: Double = 14 * 24 * 3600
    ) async throws {
        try await writer.write { db in
            // Pass 1: age-based deletion.
            let cutoff = now - maxAgeSeconds
            try db.execute(
                sql: "DELETE FROM diagnosticEvent WHERE timestamp < ?",
                arguments: [cutoff]
            )

            // Pass 2: row-count cap — keep only the newest maxRows rows.
            try db.execute(
                sql: """
                    DELETE FROM diagnosticEvent
                    WHERE id NOT IN (
                        SELECT id FROM diagnosticEvent
                        ORDER BY timestamp DESC, id DESC
                        LIMIT ?
                    )
                    """,
                arguments: [maxRows]
            )
        }
    }

    // MARK: - Clear

    /// Deletes all rows from the `diagnosticEvent` table.
    func clearDiagnosticEvents() async throws {
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM diagnosticEvent")
        }
    }
}
