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
    /// Returns a live `AsyncStream` of diagnostic events matching `filter`,
    /// ordered newest-first (`timestamp DESC, id DESC`).
    ///
    /// The stream emits an initial snapshot immediately after subscription (the
    /// standard `ValueObservation` contract), then re-emits every time the
    /// `diagnosticEvent` table changes in a way that affects the filtered result
    /// set. Duplicate-equal snapshots are suppressed via `.removeDuplicates()`.
    ///
    /// The stream finishes (and logs an error) if the underlying
    /// `ValueObservation` encounters an unrecoverable database error.
    ///
    /// Filter semantics match `recentDiagnosticEvents(_:)`:
    /// - `nil` or empty `categories` set — no category restriction.
    /// - `minimumLevel` — rows with a lower `level` integer are excluded.
    /// - `searchText` — trimmed; applied as a LIKE substring across `message`,
    ///   `event`, `instance`, and `metadata` when non-empty.
    /// - `limit` — caps the number of rows per emission (newest kept).
    ///
    /// - Parameter filter: Constrains which events are included in each emission.
    /// - Returns: An `AsyncStream` that yields `[DiagnosticEventRecord]` arrays.
    func observeDiagnosticEvents(_ filter: DiagnosticLogFilter) -> AsyncStream<[DiagnosticEventRecord]> {
        let observation = ValueObservation
            .tracking { db -> [DiagnosticEventRecord] in
                try Self.diagnosticEventQuery(filter: filter).fetchAll(db)
            }
            .removeDuplicates()

        return AsyncStream { continuation in
            // ValueObservation.start defaults to .async(onQueue: .main), which
            // is @MainActor-isolated and illegal from this non-isolated AsyncStream
            // init closure. All *Observations.swift helpers in this project use
            // .async(onQueue: .global(qos: .userInitiated)) explicitly.
            let cancellable = observation.start(
                in: writer,
                scheduling: .async(onQueue: .global(qos: .userInitiated))
            ) { error in
                logger.error("observeDiagnosticEvents ValueObservation failed: \(String(describing: error), privacy: .public)")
                continuation.finish()
            } onChange: { value in
                continuation.yield(value)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }
}

// MARK: - Shared query builder

extension AppDatabase {
    /// Builds the filtered `QueryInterfaceRequest<DiagnosticEventRecord>` shared
    /// by `recentDiagnosticEvents` and `observeDiagnosticEvents`.  Keeping this
    /// in one place ensures both the sync and live paths apply identical
    /// predicates.
    static func diagnosticEventQuery(filter: DiagnosticLogFilter) -> QueryInterfaceRequest<DiagnosticEventRecord> {
        var predicates: [SQLExpression] = []

        // Level filter — stored as Int, compared numerically.
        predicates.append(Column("level") >= filter.minimumLevel.rawValue)

        // Category filter — only apply when the set is non-nil AND non-empty.
        // nil or [] both mean "no category filter = all categories".
        if let cats = filter.categories, !cats.isEmpty {
            let rawValues = cats.map(\.rawValue)
            predicates.append(rawValues.contains(Column("category")))
        }

        // Free-text search — trimmed, applied only when non-empty.
        let searchTerm = filter.searchText?.trimmingCharacters(in: .whitespaces) ?? ""
        if !searchTerm.isEmpty {
            let pattern = "%\(searchTerm)%"
            let textPredicate = Column("message").like(pattern)
                || Column("event").like(pattern)
                || Column("instance").like(pattern)
                || Column("metadata").like(pattern)
            predicates.append(textPredicate)
        }

        var query = DiagnosticEventRecord.all()
        for predicate in predicates {
            query = query.filter(predicate)
        }

        return query
            .order(Column("timestamp").desc, Column("id").desc)
            .limit(filter.limit)
    }
}
