//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

public struct CommunityRecord: Codable, Sendable, Equatable, Identifiable {
    public static let databaseTableName = "community"

    public var id: Int64?
    public var accountId: Int64
    public var communityId: Int64
    public var name: String?
    public var title: String?
    public var actorId: String?
    public var descriptionText: String?
    public var iconUrl: String?
    public var bannerUrl: String?
    public var isHidden: Bool
    public var isLocal: Bool
    public var isNsfw: Bool
    public var isPostingRestrictedToMods: Bool
    public var isRemoved: Bool
    public var communityCreatedDate: Date?
    public var communityUpdatedDate: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: Int64? = nil,
        accountId: Int64,
        communityId: Int64,
        name: String? = nil,
        title: String? = nil,
        actorId: String? = nil,
        descriptionText: String? = nil,
        iconUrl: String? = nil,
        bannerUrl: String? = nil,
        isHidden: Bool = false,
        isLocal: Bool = false,
        isNsfw: Bool = false,
        isPostingRestrictedToMods: Bool = false,
        isRemoved: Bool = false,
        communityCreatedDate: Date? = nil,
        communityUpdatedDate: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.accountId = accountId
        self.communityId = communityId
        self.name = name
        self.title = title
        self.actorId = actorId
        self.descriptionText = descriptionText
        self.iconUrl = iconUrl
        self.bannerUrl = bannerUrl
        self.isHidden = isHidden
        self.isLocal = isLocal
        self.isNsfw = isNsfw
        self.isPostingRestrictedToMods = isPostingRestrictedToMods
        self.isRemoved = isRemoved
        self.communityCreatedDate = communityCreatedDate
        self.communityUpdatedDate = communityUpdatedDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension CommunityRecord: FetchableRecord, MutablePersistableRecord {
    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public struct AccountFollowedCommunityRecord: Codable, Sendable, Equatable {
    public static let databaseTableName = "accountFollowedCommunity"

    public var accountId: Int64
    public var communityId: Int64

    public init(accountId: Int64, communityId: Int64) {
        self.accountId = accountId
        self.communityId = communityId
    }
}

extension AccountFollowedCommunityRecord: FetchableRecord, PersistableRecord { }
