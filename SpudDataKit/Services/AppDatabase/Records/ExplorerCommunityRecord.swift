//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

/// Global, cross-instance community directory row sourced from Lemmy Explorer
/// (data.lemmyverse.net). Not account-scoped — distinct from ``CommunityRecord``
/// which carries the signed-in account's subscription state.
public struct ExplorerCommunityRecord: Codable, Sendable, Equatable, Identifiable {
    public static let databaseTableName = "explorerCommunity"

    public var id: Int64?
    /// Community actor id, e.g. "https://lemmy.world/c/technology". Unique key.
    public var url: String
    /// Home instance host, e.g. "lemmy.world". Used to group duplicates.
    public var baseurl: String
    public var name: String
    public var title: String?
    public var descriptionText: String?
    public var iconUrl: String?
    public var bannerUrl: String?
    public var isNsfw: Bool
    public var numberOfSubscribers: Int64
    public var numberOfPosts: Int64
    public var numberOfComments: Int64
    public var usersActiveDay: Int64
    public var usersActiveWeek: Int64
    public var usersActiveMonth: Int64
    public var usersActiveHalfYear: Int64
    /// Lemmy Explorer ranking score.
    public var score: Double
    public var isSuspicious: Bool
    /// Stamp of the refresh that wrote this row; used to prune stale rows.
    public var updatedAt: Date

    public init(
        id: Int64? = nil,
        url: String,
        baseurl: String,
        name: String,
        title: String? = nil,
        descriptionText: String? = nil,
        iconUrl: String? = nil,
        bannerUrl: String? = nil,
        isNsfw: Bool = false,
        numberOfSubscribers: Int64 = 0,
        numberOfPosts: Int64 = 0,
        numberOfComments: Int64 = 0,
        usersActiveDay: Int64 = 0,
        usersActiveWeek: Int64 = 0,
        usersActiveMonth: Int64 = 0,
        usersActiveHalfYear: Int64 = 0,
        score: Double = 0,
        isSuspicious: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.url = url
        self.baseurl = baseurl
        self.name = name
        self.title = title
        self.descriptionText = descriptionText
        self.iconUrl = iconUrl
        self.bannerUrl = bannerUrl
        self.isNsfw = isNsfw
        self.numberOfSubscribers = numberOfSubscribers
        self.numberOfPosts = numberOfPosts
        self.numberOfComments = numberOfComments
        self.usersActiveDay = usersActiveDay
        self.usersActiveWeek = usersActiveWeek
        self.usersActiveMonth = usersActiveMonth
        self.usersActiveHalfYear = usersActiveHalfYear
        self.score = score
        self.isSuspicious = isSuspicious
        self.updatedAt = updatedAt
    }
}

extension ExplorerCommunityRecord: FetchableRecord, MutablePersistableRecord {
    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public extension ExplorerCommunityRecord {
    enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let url = Column(CodingKeys.url)
        public static let baseurl = Column(CodingKeys.baseurl)
        public static let name = Column(CodingKeys.name)
        public static let numberOfSubscribers = Column(CodingKeys.numberOfSubscribers)
        public static let usersActiveMonth = Column(CodingKeys.usersActiveMonth)
        public static let score = Column(CodingKeys.score)
        public static let isNsfw = Column(CodingKeys.isNsfw)
        public static let updatedAt = Column(CodingKeys.updatedAt)
    }
}
