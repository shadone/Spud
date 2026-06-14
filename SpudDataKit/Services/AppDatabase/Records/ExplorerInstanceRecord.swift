//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

/// Global, cross-instance directory row sourced from Lemmy Explorer
/// (data.lemmyverse.net). Not account-scoped — distinct from ``InstanceRecord``
/// / ``SiteRecord`` which model instances the signed-in account interacts with.
public struct ExplorerInstanceRecord: Codable, Sendable, Equatable, Identifiable {
    public static let databaseTableName = "explorerInstance"

    public var id: Int64?
    /// Instance host, e.g. "lemmy.world". Unique key for upsert.
    public var baseurl: String
    public var url: String?
    public var name: String
    public var descriptionText: String?
    public var version: String?
    public var usersTotal: Int64
    public var usersActiveMonth: Int64
    public var usersActiveHalfYear: Int64
    public var numberOfCommunities: Int64
    public var numberOfPosts: Int64
    public var numberOfComments: Int64
    /// All-time uptime percentage (0...100), if known.
    public var uptimeAllTime: Double?
    public var latency: Double?
    public var uptimeStatus: Int64?
    /// Lemmy registration mode: -1 unknown, 0 closed, 1 require-application, 2 open.
    public var regMode: Int64
    public var isOpenRegistration: Bool
    public var isNsfw: Bool
    public var allowsDownvotes: Bool
    public var isPrivate: Bool
    public var federationEnabled: Bool
    /// Lemmy Explorer ranking score.
    public var score: Double
    public var isSuspicious: Bool
    public var iconUrl: String?
    public var bannerUrl: String?
    /// Comma-joined language codes; see ``languageCodes``.
    public var langs: String?
    /// Comma-joined tags; see ``tagList``.
    public var tags: String?
    public var blocksIncoming: Int64?
    public var blocksOutgoing: Int64?
    /// Stamp of the refresh that wrote this row; used to prune stale rows.
    public var updatedAt: Date

    public init(
        id: Int64? = nil,
        baseurl: String,
        url: String? = nil,
        name: String,
        descriptionText: String? = nil,
        version: String? = nil,
        usersTotal: Int64 = 0,
        usersActiveMonth: Int64 = 0,
        usersActiveHalfYear: Int64 = 0,
        numberOfCommunities: Int64 = 0,
        numberOfPosts: Int64 = 0,
        numberOfComments: Int64 = 0,
        uptimeAllTime: Double? = nil,
        latency: Double? = nil,
        uptimeStatus: Int64? = nil,
        regMode: Int64 = -1,
        isOpenRegistration: Bool = false,
        isNsfw: Bool = false,
        allowsDownvotes: Bool = true,
        isPrivate: Bool = false,
        federationEnabled: Bool = true,
        score: Double = 0,
        isSuspicious: Bool = false,
        iconUrl: String? = nil,
        bannerUrl: String? = nil,
        langs: String? = nil,
        tags: String? = nil,
        blocksIncoming: Int64? = nil,
        blocksOutgoing: Int64? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.baseurl = baseurl
        self.url = url
        self.name = name
        self.descriptionText = descriptionText
        self.version = version
        self.usersTotal = usersTotal
        self.usersActiveMonth = usersActiveMonth
        self.usersActiveHalfYear = usersActiveHalfYear
        self.numberOfCommunities = numberOfCommunities
        self.numberOfPosts = numberOfPosts
        self.numberOfComments = numberOfComments
        self.uptimeAllTime = uptimeAllTime
        self.latency = latency
        self.uptimeStatus = uptimeStatus
        self.regMode = regMode
        self.isOpenRegistration = isOpenRegistration
        self.isNsfw = isNsfw
        self.allowsDownvotes = allowsDownvotes
        self.isPrivate = isPrivate
        self.federationEnabled = federationEnabled
        self.score = score
        self.isSuspicious = isSuspicious
        self.iconUrl = iconUrl
        self.bannerUrl = bannerUrl
        self.langs = langs
        self.tags = tags
        self.blocksIncoming = blocksIncoming
        self.blocksOutgoing = blocksOutgoing
        self.updatedAt = updatedAt
    }
}

extension ExplorerInstanceRecord: FetchableRecord, MutablePersistableRecord {
    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public extension ExplorerInstanceRecord {
    enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let baseurl = Column(CodingKeys.baseurl)
        public static let name = Column(CodingKeys.name)
        public static let usersTotal = Column(CodingKeys.usersTotal)
        public static let usersActiveMonth = Column(CodingKeys.usersActiveMonth)
        public static let score = Column(CodingKeys.score)
        public static let isOpenRegistration = Column(CodingKeys.isOpenRegistration)
        public static let isNsfw = Column(CodingKeys.isNsfw)
        public static let updatedAt = Column(CodingKeys.updatedAt)
    }

    /// Parsed language codes from the comma-joined ``langs`` column.
    var languageCodes: [String] {
        langs?.split(separator: ",").map(String.init) ?? []
    }

    /// Parsed tags from the comma-joined ``tags`` column.
    var tagList: [String] {
        tags?.split(separator: ",").map(String.init) ?? []
    }

    /// Typed view of ``regMode``.
    var registrationMode: ExplorerRegistrationMode {
        ExplorerRegistrationMode(rawValue: Int(regMode)) ?? .unknown
    }
}

/// Lemmy instance registration mode (`reg_mode` in the Explorer schema).
public enum ExplorerRegistrationMode: Int, Sendable, Equatable {
    case unknown = -1
    case closed = 0
    case requireApplication = 1
    case open = 2
}
