//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

/// A community the user has favorited locally. Favorites are a client-side,
/// permanent concern (Lemmy has no favorites API): a favorited community is
/// pinned to the top of the subscriptions list. Unlike `MutedCommunityRecord`
/// there is no expiry — a favorite lasts until the user removes it. Scoped per
/// account.
public struct FavoritedCommunityRecord: Codable, Sendable, Equatable, Identifiable {
    public static let databaseTableName = "favoritedCommunity"

    public var id: Int64?
    public var accountId: Int64
    /// The community's federation actor id (e.g. "https://lemmy.world/c/world").
    /// Stable across instances, so it matches the community regardless of which
    /// feed surfaced it.
    public var communityActorId: String
    public var createdAt: Date

    public init(
        id: Int64? = nil,
        accountId: Int64,
        communityActorId: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.accountId = accountId
        self.communityActorId = communityActorId
        self.createdAt = createdAt
    }
}

extension FavoritedCommunityRecord: FetchableRecord, MutablePersistableRecord {
    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public extension FavoritedCommunityRecord {
    enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let accountId = Column(CodingKeys.accountId)
        public static let communityActorId = Column(CodingKeys.communityActorId)
        public static let createdAt = Column(CodingKeys.createdAt)
    }
}
