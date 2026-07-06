//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import OSLog
import SpudUtilKit

private let logger = Logger.appDatabase

public extension AppDatabase {
    /// Reactive `SummaryStats` stream for one account / person row.
    ///
    /// Combines:
    /// - Server-sourced post and comment karma + identity fields from the
    ///   `person` row identified by `personRowId`.
    /// - Four local counts (saved items, reads, vote events, followed
    ///   communities) — all account-isolated.
    ///
    /// Yields immediately on subscription (using GRDB's `.immediate`
    /// scheduling inside `ValueObservation`) and on every subsequent DB
    /// change that touches any of the observed tables. The stream never
    /// throws; errors are logged and the stream is finished.
    ///
    /// - Parameters:
    ///   - accountId: Primary key of the `account` row (used for all local
    ///     count queries).
    ///   - personRowId: Primary key of the `person` row (used for the
    ///     server-sourced karma and identity fields).
    ///   - asOf: Reference instant for the relative "joined" age string.
    ///     Defaults to the current wall clock (production); snapshot/unit tests
    ///     inject a fixed date so the rendered age is deterministic and never
    ///     leaks the record-time clock.
    func observeSummaryStats(
        accountId: Int64,
        personRowId: Int64,
        asOf: Date = Date()
    ) -> AsyncStream<SummaryStats> {
        let observation = ValueObservation
            .tracking { db -> SummaryStats in
                // Server-sourced identity + karma ---------------------------------
                // NOTE: We re-implement the person SELECT inline rather than
                // composing `observePersonProfile`. `ValueObservation.tracking`
                // requires all reads to happen within a single database transaction
                // so that GRDB can record the observed tables atomically. Nesting
                // one `ValueObservation` inside another's `tracking` closure is not
                // supported — the inner observation would start its own transaction,
                // breaking the atomicity guarantee and causing a runtime assertion.
                // The inline 4-column projection is intentionally minimal; it mirrors
                // the `COALESCE(displayName, name)` fallback that `PersonProfileRow`
                // uses so the display name semantics are consistent.
                let personRow = try Row.fetchOne(
                    db,
                    sql: """
                        SELECT
                            COALESCE(person.displayName, person.name) AS personName,
                            person.numberOfPosts                       AS numberOfPosts,
                            person.numberOfComments                    AS numberOfComments,
                            person.personCreatedDate                   AS personCreatedDate
                        FROM person
                        WHERE person.id = ?
                        """,
                    arguments: [personRowId]
                )

                let personName: String = personRow?["personName"] ?? ""
                let numberOfPosts: Int64 = personRow?["numberOfPosts"] ?? 0
                let numberOfComments: Int64 = personRow?["numberOfComments"] ?? 0
                let personCreatedDate: Date? = personRow?["personCreatedDate"]

                // Local counts ---------------------------------------------------
                let savedCount = try Int.fetchOne(
                    db,
                    sql: "SELECT count(*) FROM post WHERE accountId = ? AND isSaved = 1",
                    arguments: [accountId]
                ) ?? 0
                let savedCommentCount = try Int.fetchOne(
                    db,
                    sql: """
                        SELECT count(*)
                        FROM comment
                        JOIN post ON post.id = comment.postId
                        WHERE post.accountId = ? AND comment.isSaved = 1
                        """,
                    arguments: [accountId]
                ) ?? 0
                let readCount = try Int.fetchOne(
                    db,
                    sql: """
                        SELECT count(*)
                        FROM postInteraction
                        WHERE accountId = ? AND lastOpenedAt IS NOT NULL
                        """,
                    arguments: [accountId]
                ) ?? 0
                let voteCount = try Int.fetchOne(
                    db,
                    sql: "SELECT count(*) FROM voteEvent WHERE accountId = ?",
                    arguments: [accountId]
                ) ?? 0
                let communityCount = try Int.fetchOne(
                    db,
                    sql: "SELECT count(*) FROM accountFollowedCommunity WHERE accountId = ?",
                    arguments: [accountId]
                ) ?? 0

                // Format identity fields -----------------------------------------
                let joined = personCreatedDate.map {
                    PersonFormatter.string(personCreatedDate: $0, asOf: asOf)
                } ?? ""
                let cakeDay = personCreatedDate.map {
                    PersonFormatter.cakeDayString(personCreatedDate: $0)
                } ?? ""

                // Build tiles (Posts, Comments, Saved, Votes cast,
                //              Communities, Posts read) ---------------------------
                let tiles: [SummaryStat] = [
                    SummaryStat(
                        key: "posts",
                        label: "Posts",
                        value: CountFormatter.string(numberOfPosts),
                        icon: "doc.text",
                        source: .server
                    ),
                    SummaryStat(
                        key: "comments",
                        label: "Comments",
                        value: CountFormatter.string(numberOfComments),
                        icon: "bubble.left",
                        source: .server
                    ),
                    SummaryStat(
                        key: "saved",
                        label: "Saved",
                        value: CountFormatter.string(Int64(savedCount + savedCommentCount)),
                        icon: "bookmark",
                        source: .local
                    ),
                    SummaryStat(
                        key: "votes",
                        label: "Votes cast",
                        // Forward-only tally: displays count even when 0.
                        value: CountFormatter.string(Int64(voteCount)),
                        icon: "arrow.up.arrow.down",
                        source: .forward,
                        note: "new"
                    ),
                    SummaryStat(
                        key: "communities",
                        label: "Communities",
                        value: CountFormatter.string(Int64(communityCount)),
                        icon: "person.3",
                        source: .server
                    ),
                    SummaryStat(
                        key: "read",
                        label: "Posts read",
                        value: CountFormatter.string(Int64(readCount)),
                        icon: "eye",
                        source: .local
                    ),
                ]

                return SummaryStats(
                    tiles: tiles,
                    name: personName,
                    joined: joined,
                    cakeDay: cakeDay
                )
            }
            .removeDuplicates()

        return AsyncStream { continuation in
            let cancellable = observation.start(
                in: writer,
                scheduling: .async(onQueue: .global(qos: .userInitiated))
            ) { error in
                logger.error("SummaryStats observation failed: \(String(describing: error), privacy: .public)")
                continuation.finish()
            } onChange: { value in
                continuation.yield(value)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }
}
