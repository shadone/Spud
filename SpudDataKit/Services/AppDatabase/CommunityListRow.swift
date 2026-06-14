//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Snapshot row for the community Discover surfaces (directory, rails, compare
/// sheet), sourced from the Lemmy Explorer community directory
/// (``ExplorerCommunityRecord``). Not account-scoped — distinct from the
/// signed-in account's subscription state in ``CommunityRecord``.
///
/// The two `also*`/`group*` fields are populated by ``ExplorerCommunityDirectory``
/// when it collapses same-name communities across servers; they are zero on a
/// plain, un-deduplicated row.
public struct CommunityListRow: Sendable, Equatable, Identifiable {
    public let id: Int64
    /// Community actor id, e.g. "https://lemmy.world/c/technology".
    public let communityUrl: String
    /// Home instance host, e.g. "lemmy.world".
    public let instanceHost: String
    public let name: String
    public let title: String?
    public let descriptionText: String?
    public let iconUrl: URL?
    public let isNsfw: Bool
    public let isSuspicious: Bool
    public let numberOfSubscribers: Int64
    public let numberOfPosts: Int64
    public let numberOfComments: Int64
    public let usersActiveWeek: Int64
    public let usersActiveMonth: Int64
    public let score: Double
    /// Community creation date (Lemmy `community.published`), when known. Backs
    /// the "Newest" sort; nil rows sort last.
    public let publishedAt: Date?

    /// Number of OTHER servers hosting a community with the same name; 0 when
    /// unique or when the list is not deduplicated.
    public var alsoOnServerCount: Int
    /// Total subscribers summed across every same-name variant (this row
    /// included); 0 when not deduplicated.
    public var groupTotalSubscribers: Int64

    public init(
        id: Int64,
        communityUrl: String,
        instanceHost: String,
        name: String,
        title: String? = nil,
        descriptionText: String? = nil,
        iconUrl: URL? = nil,
        isNsfw: Bool = false,
        isSuspicious: Bool = false,
        numberOfSubscribers: Int64 = 0,
        numberOfPosts: Int64 = 0,
        numberOfComments: Int64 = 0,
        usersActiveWeek: Int64 = 0,
        usersActiveMonth: Int64 = 0,
        score: Double = 0,
        publishedAt: Date? = nil,
        alsoOnServerCount: Int = 0,
        groupTotalSubscribers: Int64 = 0
    ) {
        self.id = id
        self.communityUrl = communityUrl
        self.instanceHost = instanceHost
        self.name = name
        self.title = title
        self.descriptionText = descriptionText
        self.iconUrl = iconUrl
        self.isNsfw = isNsfw
        self.isSuspicious = isSuspicious
        self.numberOfSubscribers = numberOfSubscribers
        self.numberOfPosts = numberOfPosts
        self.numberOfComments = numberOfComments
        self.usersActiveWeek = usersActiveWeek
        self.usersActiveMonth = usersActiveMonth
        self.score = score
        self.publishedAt = publishedAt
        self.alsoOnServerCount = alsoOnServerCount
        self.groupTotalSubscribers = groupTotalSubscribers
    }

    /// Human label for the community — its title if present, else the bare name.
    public var displayName: String {
        title ?? name
    }
}
