//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import Testing
@testable import SpudDataKit

struct FavoritedCommunityQueriesTests {
    /// Seeds the minimal account graph (instance -> site -> account) and returns
    /// the account row id. `keychainId` lets multiple accounts coexist.
    @discardableResult
    private func seedAccount(_ appDatabase: AppDatabase, keychainId: String) async throws -> Int64 {
        try await appDatabase.writer.write { db in
            try db.execute(sql: "INSERT INTO instance (actorId, createdAt) VALUES (?, ?)", arguments: ["https://\(keychainId).test", Date()])
            let instanceId = db.lastInsertedRowID
            try db.execute(sql: "INSERT INTO site (instanceId, createdAt, updatedAt) VALUES (?, ?, ?)", arguments: [instanceId, Date(), Date()])
            let siteId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO account (siteId, accountKeychainId, isDefault, isServiceAccount, isSignedOutAccountType, createdAt, updatedAt)
                VALUES (?, ?, 0, 0, 0, ?, ?)
                """, arguments: [siteId, keychainId, Date(), Date()])
            return db.lastInsertedRowID
        }
    }

    private static let community = "https://lemmy.world/c/world"
    private var community: String {
        Self.community
    }

    @Test
    func migration_createsTable() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let exists = try await appDatabase.writer.read { try $0.tableExists("favoritedCommunity") }
        #expect(exists)
    }

    @Test
    func favorite_thenIsFavoritedTrue() async throws {
        let appDatabase = try AppDatabase.inMemory()
        try await seedAccount(appDatabase, keychainId: "kc-1")

        #expect(!(appDatabase.isCommunityFavoritedSync(forKeychainId: "kc-1", communityActorId: community)))

        appDatabase.favoriteCommunitySync(forKeychainId: "kc-1", communityActorId: community)

        #expect(appDatabase.isCommunityFavoritedSync(forKeychainId: "kc-1", communityActorId: community))
    }

    @Test
    func unfavorite_thenIsFavoritedFalse() async throws {
        let appDatabase = try AppDatabase.inMemory()
        try await seedAccount(appDatabase, keychainId: "kc-1")

        appDatabase.favoriteCommunitySync(forKeychainId: "kc-1", communityActorId: community)
        #expect(appDatabase.isCommunityFavoritedSync(forKeychainId: "kc-1", communityActorId: community))

        appDatabase.unfavoriteCommunitySync(forKeychainId: "kc-1", communityActorId: community)
        #expect(!(appDatabase.isCommunityFavoritedSync(forKeychainId: "kc-1", communityActorId: community)))
    }

    /// Favoriting twice must not create a duplicate row (idempotent upsert).
    @Test
    func favorite_isIdempotent() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let accountId = try await seedAccount(appDatabase, keychainId: "kc-1")

        appDatabase.favoriteCommunitySync(forKeychainId: "kc-1", communityActorId: community)
        appDatabase.favoriteCommunitySync(forKeychainId: "kc-1", communityActorId: community)

        let actorId = community
        let count = try await appDatabase.writer.read { db in
            try FavoritedCommunityRecord
                .filter(Column("accountId") == accountId)
                .filter(Column("communityActorId") == actorId)
                .fetchCount(db)
        }
        #expect(count == 1)
    }

    /// Favorites are scoped per account: favoriting on one account must not leak
    /// into another.
    @Test
    func favorites_areIsolatedPerAccount() async throws {
        let appDatabase = try AppDatabase.inMemory()
        try await seedAccount(appDatabase, keychainId: "kc-1")
        try await seedAccount(appDatabase, keychainId: "kc-2")

        appDatabase.favoriteCommunitySync(forKeychainId: "kc-1", communityActorId: community)

        #expect(appDatabase.isCommunityFavoritedSync(forKeychainId: "kc-1", communityActorId: community))
        #expect(!(appDatabase.isCommunityFavoritedSync(forKeychainId: "kc-2", communityActorId: community)))
    }

    /// An unknown keychain id is a no-op for writes and reports not-favorited.
    @Test
    func unknownAccount_noOps() throws {
        let appDatabase = try AppDatabase.inMemory()
        appDatabase.favoriteCommunitySync(forKeychainId: "missing", communityActorId: community)
        #expect(!(appDatabase.isCommunityFavoritedSync(forKeychainId: "missing", communityActorId: community)))
    }

    @Test
    func observation_emitsCurrentAndUpdatedFavorites() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let accountId = try await seedAccount(appDatabase, keychainId: "kc-1")

        appDatabase.favoriteCommunitySync(forKeychainId: "kc-1", communityActorId: community)

        var iterator = appDatabase.observeFavoritedCommunityActorIds(forAccountId: accountId).makeAsyncIterator()

        let first = await iterator.next()
        #expect(first == Set([community]))

        let other = "https://lemmy.world/c/news"
        appDatabase.favoriteCommunitySync(forKeychainId: "kc-1", communityActorId: other)

        let second = await iterator.next()
        #expect(second == Set([community, other]))
    }
}
