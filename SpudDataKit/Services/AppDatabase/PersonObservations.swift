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
    /// Whether the person is banned at the instance level. `banExpires` is the
    /// expiry of a temporary ban (nil = permanent when `isBanned`, or simply not
    /// banned).
    public let isBanned: Bool
    public let banExpires: Date?
    /// The user deleted their own account.
    public let isDeleted: Bool
    public let isBotAccount: Bool
    /// Whether the person is an admin of the instance. Only known after a full
    /// `PersonView` import (a bare creator import leaves it false).
    public let isAdmin: Bool
    public let matrixUserId: String?
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

    /// Resolves a person's display name (falling back to their handle) by
    /// `(accountKeychainId, server person id)`, matching the account-keyed lookup
    /// of `personRowIdSync`. Returns nil when the person row isn't present yet
    /// (e.g. a DM recipient typed before any message was imported). Synchronous
    /// for view-controller bring-up and list-cell labeling paths.
    ///
    /// Used to name an outbound DM recipient — both the Drafts & Outbox "Message
    /// to <name>" row and a synthetic pending-only conversation row in the inbox
    /// list — without a full `PersonProfileRow` join.
    func personDisplayNameSync(forKeychainId keychainId: String, personId: Int64) -> String? {
        do {
            return try writer.read { db -> String? in
                let siteId: Int64? = try AccountRecord
                    .filter(Column("accountKeychainId") == keychainId)
                    .fetchOne(db)?
                    .siteId
                guard let siteId else { return nil }
                guard let person = try PersonRecord
                    .filter(Column("siteId") == siteId)
                    .filter(Column("personId") == personId)
                    .fetchOne(db)
                else {
                    return nil
                }
                // displayName falls back to the handle, mirroring the SQL
                // `coalescingString("displayName", "name")` used by the list reads.
                return person.displayName ?? person.name
            }
        } catch {
            logger.error("Failed to resolve person display name by keychainId: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Resolves a person's display name (falling back to their handle) AND avatar
    /// URL together by `(accountKeychainId, server person id)`, in a SINGLE
    /// `writer.read`. The combined sibling of `personDisplayNameSync` /
    /// `personAvatarUrlSync`: when a caller needs both fields it would otherwise
    /// take two blocking reads per person, which on the inbox `@MainActor`
    /// recompute (once per correspondent, on every observation tick) is wasteful.
    ///
    /// Returns nil only when the person row isn't present yet (e.g. a DM recipient
    /// typed before any message was imported); when the row exists, `name` is the
    /// `displayName ?? handle` and `avatarUrl` is whatever the row carries (which
    /// can itself be nil). Synchronous for the list-cell labeling path that names
    /// a synthetic pending-only DM correspondent.
    func personNameAndAvatarSync(
        forKeychainId keychainId: String,
        personId: Int64
    ) -> (name: String?, avatarUrl: String?)? {
        do {
            return try writer.read { db -> (name: String?, avatarUrl: String?)? in
                let siteId: Int64? = try AccountRecord
                    .filter(Column("accountKeychainId") == keychainId)
                    .fetchOne(db)?
                    .siteId
                guard let siteId else { return nil }
                guard let person = try PersonRecord
                    .filter(Column("siteId") == siteId)
                    .filter(Column("personId") == personId)
                    .fetchOne(db)
                else {
                    return nil
                }
                // displayName falls back to the handle, mirroring the SQL
                // `coalescingString("displayName", "name")` used by the list reads.
                return (name: person.displayName ?? person.name, avatarUrl: person.avatarUrl)
            }
        } catch {
            logger.error("Failed to resolve person name and avatar by keychainId: \(String(describing: error), privacy: .public)")
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
                            person.isBanned          AS isBanned,
                            person.banExpires        AS banExpires,
                            person.isDeleted         AS isDeleted,
                            person.isBotAccount      AS isBotAccount,
                            person.isAdmin           AS isAdmin,
                            person.matrixUserId      AS matrixUserId,
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
                    personCreatedDate: row["personCreatedDate"],
                    isBanned: row["isBanned"],
                    banExpires: row["banExpires"],
                    isDeleted: row["isDeleted"],
                    isBotAccount: row["isBotAccount"],
                    isAdmin: row["isAdmin"],
                    matrixUserId: row["matrixUserId"]
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
