//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

public struct PersonRecord: Codable, Sendable, Equatable, Identifiable {
    public static let databaseTableName = "person"

    public var id: Int64?
    public var siteId: Int64
    public var personId: Int64
    public var name: String?
    public var displayName: String?
    public var avatarUrl: String?
    public var bannerUrl: String?
    public var bio: String?
    public var actorId: String?
    public var matrixUserId: String?
    public var isAdmin: Bool
    public var isBanned: Bool
    public var isBotAccount: Bool
    public var isDeleted: Bool
    public var isLocal: Bool
    public var numberOfPosts: Int64
    public var numberOfComments: Int64
    public var banExpires: Date?
    public var personCreatedDate: Date?
    public var personUpdatedDate: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: Int64? = nil,
        siteId: Int64,
        personId: Int64,
        name: String? = nil,
        displayName: String? = nil,
        avatarUrl: String? = nil,
        bannerUrl: String? = nil,
        bio: String? = nil,
        actorId: String? = nil,
        matrixUserId: String? = nil,
        isAdmin: Bool = false,
        isBanned: Bool = false,
        isBotAccount: Bool = false,
        isDeleted: Bool = false,
        isLocal: Bool = false,
        numberOfPosts: Int64 = 0,
        numberOfComments: Int64 = 0,
        banExpires: Date? = nil,
        personCreatedDate: Date? = nil,
        personUpdatedDate: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.siteId = siteId
        self.personId = personId
        self.name = name
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.bannerUrl = bannerUrl
        self.bio = bio
        self.actorId = actorId
        self.matrixUserId = matrixUserId
        self.isAdmin = isAdmin
        self.isBanned = isBanned
        self.isBotAccount = isBotAccount
        self.isDeleted = isDeleted
        self.isLocal = isLocal
        self.numberOfPosts = numberOfPosts
        self.numberOfComments = numberOfComments
        self.banExpires = banExpires
        self.personCreatedDate = personCreatedDate
        self.personUpdatedDate = personUpdatedDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension PersonRecord: FetchableRecord, MutablePersistableRecord {
    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
