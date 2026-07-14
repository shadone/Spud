//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

/// A community classified as "meta" (about the instance itself) for a given
/// instance, cached per account. Populated by `MetaCommunityService` from a
/// fixed candidate-name resolution pass. Holds identity only — live subscribe /
/// favourite state is joined from `community` / `favoritedCommunity` at render.
public struct InstanceMetaCommunityRecord: Codable, Sendable, Equatable, Identifiable {
    public static let databaseTableName = "instanceMetaCommunity"

    public var id: Int64?
    public var accountId: Int64
    /// The instance the community is meta *for* (e.g. "discuss.tchncs.de").
    public var instanceHost: String
    /// The community's federation actor id (e.g. "https://discuss.tchncs.de/c/tchncs").
    public var communityActorId: String
    /// `MetaConfidence` raw value: "high" | "low".
    public var confidence: String
    /// `MetaReason` raw value.
    public var reason: String
    public var discoveredAt: Date

    public init(
        id: Int64? = nil,
        accountId: Int64,
        instanceHost: String,
        communityActorId: String,
        confidence: String,
        reason: String,
        discoveredAt: Date = Date()
    ) {
        self.id = id
        self.accountId = accountId
        self.instanceHost = instanceHost
        self.communityActorId = communityActorId
        self.confidence = confidence
        self.reason = reason
        self.discoveredAt = discoveredAt
    }
}

extension InstanceMetaCommunityRecord: FetchableRecord, MutablePersistableRecord {
    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public extension InstanceMetaCommunityRecord {
    enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let accountId = Column(CodingKeys.accountId)
        public static let instanceHost = Column(CodingKeys.instanceHost)
        public static let communityActorId = Column(CodingKeys.communityActorId)
        public static let confidence = Column(CodingKeys.confidence)
        public static let reason = Column(CodingKeys.reason)
        public static let discoveredAt = Column(CodingKeys.discoveredAt)
    }
}
