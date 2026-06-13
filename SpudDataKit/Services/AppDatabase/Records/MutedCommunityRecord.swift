//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

/// A community the user has muted locally. Muting is a client-side, timed
/// view concern (Lemmy has no timed-mute API): posts from a muted community
/// are filtered out of the feed until `mutedUntil` passes. `mutedUntil == nil`
/// means muted indefinitely. Scoped per account.
public struct MutedCommunityRecord: Codable, Sendable, Equatable, Identifiable {
    public static let databaseTableName = "mutedCommunity"

    public var id: Int64?
    public var accountId: Int64
    /// The community's federation actor id (e.g. "https://lemmy.world/c/world").
    /// Stable across instances, so it matches posts regardless of which feed
    /// surfaced them.
    public var communityActorId: String
    /// When the mute expires. `nil` means muted forever.
    public var mutedUntil: Date?
    public var createdAt: Date

    public init(
        id: Int64? = nil,
        accountId: Int64,
        communityActorId: String,
        mutedUntil: Date?,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.accountId = accountId
        self.communityActorId = communityActorId
        self.mutedUntil = mutedUntil
        self.createdAt = createdAt
    }
}

extension MutedCommunityRecord: FetchableRecord, MutablePersistableRecord {
    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public extension MutedCommunityRecord {
    enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let accountId = Column(CodingKeys.accountId)
        public static let communityActorId = Column(CodingKeys.communityActorId)
        public static let mutedUntil = Column(CodingKeys.mutedUntil)
        public static let createdAt = Column(CodingKeys.createdAt)
    }
}
