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
    public let avatarUrl: String?
    public let bannerUrl: String?
    public let bio: String?
    public let actorId: String?
    public let numberOfPosts: Int64
    public let numberOfComments: Int64
    public let personCreatedDate: Date?
}

public extension AppDatabase {
    /// Resolves the row id of a person by `(accountKeychainId, server person id)`.
    /// Persons are stored under the account's site, so this account-keyed lookup
    /// matches storage regardless of the person's federated home instance (a
    /// home-instance-keyed lookup would fail for a person whose home instance
    /// differs from the account's). Synchronous for view-controller bring-up
    /// paths.
    func personRowIdSync(forKeychainId keychainId: String, personId: Int64) -> Int64? {
        do {
            return try writer.read { db in
                let siteId: Int64? = try AccountRecord
                    .filter(Column("accountKeychainId") == keychainId)
                    .fetchOne(db)?
                    .siteId
                guard let siteId else { return nil }
                return try PersonRecord
                    .filter(Column("siteId") == siteId)
                    .filter(Column("personId") == personId)
                    .fetchOne(db)?
                    .id
            }
        } catch {
            logger.error("Failed to resolve person row id by keychainId: \(String(describing: error), privacy: .public)")
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
                            person.avatarUrl         AS avatarUrl,
                            person.bannerUrl         AS bannerUrl,
                            person.bio               AS bio,
                            person.actorId           AS personActorId,
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

                // Derive the displayed host from the person's OWN actor_id
                // (e.g. lemmy.world for a remote user), NOT the joined
                // `instance.actorId`: persons are stored under the account's
                // site, so that join yields the account's home instance, which
                // would wrongly render every remote user as @<home-instance>.
                // Fall back to the account instance only when the person has no
                // actor_id yet.
                let personActorId: String? = row["personActorId"]
                let instanceActorId: String = row["instanceActorId"]
                let hostSource = personActorId ?? instanceActorId
                let host = URL(string: hostSource)?.host ?? hostSource
                return PersonProfileRow(
                    id: row["id"],
                    name: row["name"] ?? "",
                    displayName: row["displayName"],
                    instanceHostname: host,
                    avatarUrl: row["avatarUrl"],
                    bannerUrl: row["bannerUrl"],
                    bio: row["bio"],
                    actorId: row["personActorId"],
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
