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
    /// Mutes `communityActorId` for the account identified by `keychainId`
    /// until `until` (`nil` = forever). Replaces any existing mute for the same
    /// community. Synchronous to keep the context-menu path simple.
    func muteCommunitySync(
        forKeychainId keychainId: String,
        communityActorId: String,
        until: Date?
    ) {
        do {
            try writer.write { db in
                guard let accountId = try Self.accountId(db, keychainId: keychainId) else { return }
                try MutedCommunityRecord
                    .filter(Column("accountId") == accountId)
                    .filter(Column("communityActorId") == communityActorId)
                    .deleteAll(db)
                var record = MutedCommunityRecord(
                    accountId: accountId,
                    communityActorId: communityActorId,
                    mutedUntil: until
                )
                try record.insert(db)
            }
        } catch {
            logger.error("muteCommunitySync failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Removes any mute for `communityActorId` on the account identified by
    /// `keychainId`.
    func unmuteCommunitySync(
        forKeychainId keychainId: String,
        communityActorId: String
    ) {
        do {
            try writer.write { db in
                guard let accountId = try Self.accountId(db, keychainId: keychainId) else { return }
                try MutedCommunityRecord
                    .filter(Column("accountId") == accountId)
                    .filter(Column("communityActorId") == communityActorId)
                    .deleteAll(db)
            }
        } catch {
            logger.error("unmuteCommunitySync failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Whether `communityActorId` is currently muted (and not expired) for the
    /// account identified by `keychainId`.
    func isCommunityMutedSync(
        forKeychainId keychainId: String,
        communityActorId: String
    ) -> Bool {
        do {
            return try writer.read { db in
                guard let accountId = try Self.accountId(db, keychainId: keychainId) else { return false }
                guard let record = try MutedCommunityRecord
                    .filter(Column("accountId") == accountId)
                    .filter(Column("communityActorId") == communityActorId)
                    .fetchOne(db)
                else { return false }
                return Self.isActive(record)
            }
        } catch {
            logger.error("isCommunityMutedSync failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// The set of community actor ids currently muted (and not expired) for the
    /// account that owns `feedId`. Read inside the feed's `ValueObservation` so
    /// the feed re-filters whenever a mute is added or removed.
    ///
    /// Mute only hides communities from aggregate frontpage feeds (All / Local /
    /// Subscribed). A community's own feed and the saved feed are views the user
    /// opted into explicitly, so they're never filtered (otherwise visiting a
    /// muted community would show an empty screen).
    internal static func activeMutedCommunityActorIds(
        _ db: Database,
        feedId: Int64
    ) throws -> Set<String> {
        guard
            let feed = try FeedRecord
            .filter(Column("id") == feedId)
            .fetchOne(db),
            feed.frontpageListingType != nil
        else { return [] }

        let records = try MutedCommunityRecord
            .filter(Column("accountId") == feed.accountId)
            .fetchAll(db)
        return Set(records.lazy.filter(isActive).map(\.communityActorId))
    }

    private static func accountId(_ db: Database, keychainId: String) throws -> Int64? {
        try AccountRecord
            .filter(Column("accountKeychainId") == keychainId)
            .fetchOne(db)?
            .id
    }

    /// A mute is active when it has no expiry, or its expiry is in the future.
    private static func isActive(_ record: MutedCommunityRecord) -> Bool {
        guard let mutedUntil = record.mutedUntil else { return true }
        return mutedUntil > Date()
    }
}
