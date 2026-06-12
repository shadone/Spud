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
    /// Lemmy `SubscribedType` raw value: "Subscribed" / "NotSubscribed" /
    /// "Pending". Stored as text; map via ``subscribedState``.
    public var subscribedState: String
    public var numberOfSubscribers: Int64
    public var numberOfPosts: Int64
    public var numberOfComments: Int64
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
        subscribedState: String = CommunitySubscribedState.notSubscribed.rawValue,
        numberOfSubscribers: Int64 = 0,
        numberOfPosts: Int64 = 0,
        numberOfComments: Int64 = 0,
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
        self.subscribedState = subscribedState
        self.numberOfSubscribers = numberOfSubscribers
        self.numberOfPosts = numberOfPosts
        self.numberOfComments = numberOfComments
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

/// Stable mirror of LemmyKit's generated `SubscribedType`, decoupled from the
/// OpenAPI namespace so UI / persistence code can switch over the persisted
/// `CommunityRecord.subscribedState` text without importing LemmyKit.
public enum CommunitySubscribedState: String, Sendable, Equatable {
    case subscribed = "Subscribed"
    case notSubscribed = "NotSubscribed"
    case pending = "Pending"

    /// True when the account is subscribed (or has a pending request). Used to
    /// decide whether a community appears in the followed-communities sidebar
    /// and how the Subscribe/Unsubscribe toggle should behave.
    public var isSubscribed: Bool {
        switch self {
        case .subscribed, .pending: true
        case .notSubscribed: false
        }
    }
}

public extension CommunityRecord {
    /// Typed view of ``subscribedState``. Defaults to `.notSubscribed` if the
    /// stored text is unrecognised.
    var subscribed: CommunitySubscribedState {
        CommunitySubscribedState(rawValue: subscribedState) ?? .notSubscribed
    }

    /// True when the account is subscribed (i.e. the row should appear in the
    /// followed-communities sidebar). Pending counts as subscribed.
    var isSubscribed: Bool {
        subscribed.isSubscribed
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
