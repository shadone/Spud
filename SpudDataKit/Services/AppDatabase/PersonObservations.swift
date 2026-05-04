//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import OSLog

private let logger = Logger.appDatabase

/// Composite snapshot row for the Person screen. Joins person + site +
/// instance so the SwiftUI view can render without further lookups.
public struct PersonProfileRow: Sendable, Equatable, Identifiable {
    public let id: Int64
    public let name: String
    public let displayName: String?
    public let instanceHostname: String
    public let numberOfPosts: Int64
    public let numberOfComments: Int64
    public let personCreatedDate: Date?
}

public extension AppDatabase {
    /// Resolves the row id of a person by `(instance actor id, server person
    /// id)`. Synchronous so callers can wire up the observation at init time
    /// without adopting an async path purely for one lookup.
    func personRowIdSync(instanceActorId: String, personId: Int64) -> Int64? {
        do {
            return try writer.read { db in
                try Int64.fetchOne(db, sql: """
                        SELECT person.id
                        FROM person
                        JOIN site     ON site.id = person.siteId
                        JOIN instance ON instance.id = site.instanceId
                        WHERE instance.actorId = ?
                          AND person.personId = ?
                        LIMIT 1
                    """, arguments: [instanceActorId, personId])
            }
        } catch {
            logger.error("Failed to resolve person row id: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Stream of the Person profile snapshot for `personRowId`. Yields nil if
    /// the row no longer exists.
    func observePersonProfile(personRowId: Int64) -> AsyncStream<PersonProfileRow?> {
        let observation = ValueObservation
            .tracking { db -> PersonProfileRow? in
                guard let row = try Row.fetchOne(db, sql: """
                        SELECT
                            person.id                AS id,
                            person.name              AS name,
                            person.displayName       AS displayName,
                            person.numberOfPosts     AS numberOfPosts,
                            person.numberOfComments  AS numberOfComments,
                            person.personCreatedDate AS personCreatedDate,
                            instance.actorId         AS instanceActorId
                        FROM person
                        JOIN site     ON site.id = person.siteId
                        JOIN instance ON instance.id = site.instanceId
                        WHERE person.id = ?
                    """, arguments: [personRowId])
                else {
                    return nil
                }

                let actorId: String = row["instanceActorId"]
                let host = URL(string: actorId)?.host ?? actorId
                return PersonProfileRow(
                    id: row["id"],
                    name: row["name"] ?? "",
                    displayName: row["displayName"],
                    instanceHostname: host,
                    numberOfPosts: row["numberOfPosts"],
                    numberOfComments: row["numberOfComments"],
                    personCreatedDate: row["personCreatedDate"]
                )
            }
            .removeDuplicates()

        return AsyncStream { continuation in
            let cancellable = observation.start(in: writer, scheduling: .async(onQueue: .global(qos: .userInitiated))) { error in
                logger.error("PersonProfile observation failed: \(String(describing: error), privacy: .public)")
                continuation.finish()
            } onChange: { value in
                continuation.yield(value)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }
}
