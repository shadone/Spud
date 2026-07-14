//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import LemmyKit

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
    /// ``CommunitySubscribedState`` raw value: "Subscribed" / "NotSubscribed" /
    /// "Pending" and the v4-only "ApprovalRequired" / "Denied". Stored as free
    /// text (no CHECK constraint), decoded via ``CommunityRecord/subscribed``.
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

/// Stable mirror of LemmyKit's version-neutral ``FollowState``, decoupled from
/// the OpenAPI namespace so UI / persistence code can switch over the persisted
/// `CommunityRecord.subscribedState` text without importing LemmyKit.
///
/// This carries the full v4 follow vocabulary: alongside the v3-era
/// `Subscribed` / `NotSubscribed` / `Pending`, the v4-only `ApprovalRequired`
/// (the community gates joining behind moderator approval and the request is
/// awaiting a decision) and `Denied` (the moderators rejected the request) are
/// preserved distinctly rather than collapsed. A v3 backend never produces the
/// last two — its `SubscribedType` folds both into `Pending` / `NotSubscribed` —
/// so they only ever appear against a Lemmy 1.0 / v4 server.
public enum CommunitySubscribedState: String, Sendable, Equatable {
    case subscribed = "Subscribed"
    case notSubscribed = "NotSubscribed"
    case pending = "Pending"
    /// v4-only: the community requires moderator approval to join and the
    /// request is awaiting a decision. Counts as subscribed for sidebar /
    /// junction purposes (the user has an in-flight request), like ``pending``.
    case approvalRequired = "ApprovalRequired"
    /// v4-only: the community's moderators denied the follow request. Counts as
    /// NOT subscribed (no active follow) — the user may re-request.
    case denied = "Denied"

    /// True when the account is subscribed or has an in-flight request. Used to
    /// decide whether a community appears in the followed-communities sidebar and
    /// how the Subscribe/Unsubscribe toggle should behave. `subscribed`,
    /// `pending`, and `approvalRequired` all count; `denied` and `notSubscribed`
    /// do not (a denied request is no active follow — the user may re-request).
    public var isSubscribed: Bool {
        switch self {
        case .subscribed, .pending, .approvalRequired: true
        case .notSubscribed, .denied: false
        }
    }
}

public extension CommunitySubscribedState {
    /// Maps LemmyKit's version-neutral ``FollowState`` onto the persisted
    /// vocabulary 1:1, preserving the v4-only `.approvalRequired` / `.denied`
    /// distinctions rather than collapsing them. A v3 backend only ever produces
    /// `.notFollowing` / `.pending` / `.accepted`, so the two v4-only cases arise
    /// only against a Lemmy 1.0 server.
    init(followState: FollowState) {
        switch followState {
        case .accepted: self = .subscribed
        case .pending: self = .pending
        case .approvalRequired: self = .approvalRequired
        case .denied: self = .denied
        case .notFollowing: self = .notSubscribed
        }
    }
}

extension CommunitySubscribedState {
    /// Compact `Int64` encoding used as the `subscribe` outbox baseline — the
    /// PRIOR state a rollback must be able to restore.
    ///
    /// Unlike vote/save/hide (whose baseline is the same 2-valued shape as their
    /// desired state), a subscribe op's desired state is only a Bool, so a richer
    /// prior state would be lost if it round-tripped through the desired-state
    /// codec. This dedicated codec preserves every case: `0 = notSubscribed,
    /// 1 = subscribed, 2 = pending, 3 = approvalRequired, 4 = denied`. Codes
    /// `0/1/2` are UNCHANGED from the original 3-state codec, so baselines
    /// persisted before the widening still decode correctly (a legacy row can
    /// only ever hold `0/1/2`).
    var outboxBaseline: Int64 {
        switch self {
        case .notSubscribed: 0
        case .subscribed: 1
        case .pending: 2
        case .approvalRequired: 3
        case .denied: 4
        }
    }

    /// Decodes an ``outboxBaseline`` integer back to a state. Legacy rows only
    /// ever hold `0/1/2`; `3/4` are the widened v4 states. A missing (`nil`) or
    /// unrecognised value decodes to `.notSubscribed`.
    init(outboxBaseline raw: Int64?) {
        switch raw {
        case 1: self = .subscribed
        case 2: self = .pending
        case 3: self = .approvalRequired
        case 4: self = .denied
        default: self = .notSubscribed
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
