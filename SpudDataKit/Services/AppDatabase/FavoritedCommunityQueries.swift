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
    /// Favorites `communityActorId` for the account identified by `keychainId`.
    /// Idempotent: a delete-then-insert replaces any existing favorite for the
    /// same community, so calling twice doesn't duplicate the row. Synchronous to
    /// keep the overflow-menu path simple.
    func favoriteCommunitySync(
        forKeychainId keychainId: String,
        communityActorId: String
    ) {
        do {
            try writer.write { db in
                guard let accountId = try Self.favoritesAccountId(db, keychainId: keychainId) else { return }
                try FavoritedCommunityRecord
                    .filter(Column("accountId") == accountId)
                    .filter(Column("communityActorId") == communityActorId)
                    .deleteAll(db)
                var record = FavoritedCommunityRecord(
                    accountId: accountId,
                    communityActorId: communityActorId
                )
                try record.insert(db)
            }
        } catch {
            logger.error("favoriteCommunitySync failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Removes any favorite for `communityActorId` on the account identified by
    /// `keychainId`.
    func unfavoriteCommunitySync(
        forKeychainId keychainId: String,
        communityActorId: String
    ) {
        do {
            try writer.write { db in
                guard let accountId = try Self.favoritesAccountId(db, keychainId: keychainId) else { return }
                try FavoritedCommunityRecord
                    .filter(Column("accountId") == accountId)
                    .filter(Column("communityActorId") == communityActorId)
                    .deleteAll(db)
            }
        } catch {
            logger.error("unfavoriteCommunitySync failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Whether `communityActorId` is currently favorited for the account
    /// identified by `keychainId`.
    func isCommunityFavoritedSync(
        forKeychainId keychainId: String,
        communityActorId: String
    ) -> Bool {
        do {
            return try writer.read { db in
                guard let accountId = try Self.favoritesAccountId(db, keychainId: keychainId) else { return false }
                return try FavoritedCommunityRecord
                    .filter(Column("accountId") == accountId)
                    .filter(Column("communityActorId") == communityActorId)
                    .fetchCount(db) > 0
            }
        } catch {
            logger.error("isCommunityFavoritedSync failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// Stream of the set of community actor ids currently favorited for
    /// `accountId`. Yields immediately on subscription and again on every change,
    /// so the subscriptions list re-pins favorites live as the user toggles them.
    func observeFavoritedCommunityActorIds(forAccountId accountId: Int64) -> AsyncStream<Set<String>> {
        let observation = ValueObservation
            .tracking { db -> Set<String> in
                let records = try FavoritedCommunityRecord
                    .filter(Column("accountId") == accountId)
                    .fetchAll(db)
                return Set(records.map(\.communityActorId))
            }
            .removeDuplicates()

        return AsyncStream { continuation in
            let cancellable = observation.start(in: writer, scheduling: .async(onQueue: .global(qos: .userInitiated))) { error in
                logger.error("observeFavoritedCommunityActorIds failed: \(String(describing: error), privacy: .public)")
                continuation.finish()
            } onChange: { value in
                continuation.yield(value)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    private static func favoritesAccountId(_ db: Database, keychainId: String) throws -> Int64? {
        try AccountRecord
            .filter(Column("accountKeychainId") == keychainId)
            .fetchOne(db)?
            .id
    }
}
