//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

public struct SiteRecord: Codable, Sendable, Equatable, Identifiable {
    public static let databaseTableName = "site"

    public var id: Int64?
    public var instanceId: Int64
    public var name: String?
    public var descriptionText: String?
    public var sidebar: String?
    public var legalInformation: String?
    public var iconUrl: String?
    public var bannerUrl: String?
    public var version: String?
    public var defaultPostListingType: String?
    public var enableDownvotes: Bool?
    public var enableNsfw: Bool?
    public var numberOfPosts: Int64?
    public var numberOfComments: Int64?
    public var numberOfCommunities: Int64?
    public var numberOfUsers: Int64?
    public var numberOfUsersDay: Int64?
    public var numberOfUsersWeek: Int64?
    public var numberOfUsersMonth: Int64?
    public var numberOfUsersHalfYear: Int64?
    public var infoCreatedDate: Date?
    public var infoUpdatedDate: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: Int64? = nil,
        instanceId: Int64,
        name: String? = nil,
        descriptionText: String? = nil,
        sidebar: String? = nil,
        legalInformation: String? = nil,
        iconUrl: String? = nil,
        bannerUrl: String? = nil,
        version: String? = nil,
        defaultPostListingType: String? = nil,
        enableDownvotes: Bool? = nil,
        enableNsfw: Bool? = nil,
        numberOfPosts: Int64? = nil,
        numberOfComments: Int64? = nil,
        numberOfCommunities: Int64? = nil,
        numberOfUsers: Int64? = nil,
        numberOfUsersDay: Int64? = nil,
        numberOfUsersWeek: Int64? = nil,
        numberOfUsersMonth: Int64? = nil,
        numberOfUsersHalfYear: Int64? = nil,
        infoCreatedDate: Date? = nil,
        infoUpdatedDate: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.instanceId = instanceId
        self.name = name
        self.descriptionText = descriptionText
        self.sidebar = sidebar
        self.legalInformation = legalInformation
        self.iconUrl = iconUrl
        self.bannerUrl = bannerUrl
        self.version = version
        self.defaultPostListingType = defaultPostListingType
        self.enableDownvotes = enableDownvotes
        self.enableNsfw = enableNsfw
        self.numberOfPosts = numberOfPosts
        self.numberOfComments = numberOfComments
        self.numberOfCommunities = numberOfCommunities
        self.numberOfUsers = numberOfUsers
        self.numberOfUsersDay = numberOfUsersDay
        self.numberOfUsersWeek = numberOfUsersWeek
        self.numberOfUsersMonth = numberOfUsersMonth
        self.numberOfUsersHalfYear = numberOfUsersHalfYear
        self.infoCreatedDate = infoCreatedDate
        self.infoUpdatedDate = infoUpdatedDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension SiteRecord: FetchableRecord, MutablePersistableRecord {
    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
