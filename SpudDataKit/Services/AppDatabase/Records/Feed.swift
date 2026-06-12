//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

public struct FeedRecord: Codable, Sendable, Equatable, Identifiable {
    public static let databaseTableName = "feed"

    public var id: Int64?
    public var accountId: Int64
    public var feedKey: String
    public var frontpageListingType: String?
    public var communityName: String?
    public var communityInstanceActorId: String?
    /// True for the logged-in account's saved-posts feed (the `.saved`
    /// FeedType). When set, the listing/community columns are nil.
    public var savedOnly: Bool
    public var sortType: String
    public var identifierForDebugging: String?
    public var createdAt: Date

    public init(
        id: Int64? = nil,
        accountId: Int64,
        feedKey: String,
        frontpageListingType: String? = nil,
        communityName: String? = nil,
        communityInstanceActorId: String? = nil,
        savedOnly: Bool = false,
        sortType: String,
        identifierForDebugging: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.accountId = accountId
        self.feedKey = feedKey
        self.frontpageListingType = frontpageListingType
        self.communityName = communityName
        self.communityInstanceActorId = communityInstanceActorId
        self.savedOnly = savedOnly
        self.sortType = sortType
        self.identifierForDebugging = identifierForDebugging
        self.createdAt = createdAt
    }
}

extension FeedRecord: FetchableRecord, MutablePersistableRecord {
    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public struct PageRecord: Codable, Sendable, Equatable, Identifiable {
    public static let databaseTableName = "page"

    public var id: Int64?
    public var feedId: Int64
    public var position: Int64
    public var createdAt: Date

    public init(
        id: Int64? = nil,
        feedId: Int64,
        position: Int64,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.feedId = feedId
        self.position = position
        self.createdAt = createdAt
    }
}

extension PageRecord: FetchableRecord, MutablePersistableRecord {
    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public struct PageElementRecord: Codable, Sendable, Equatable, Identifiable {
    public static let databaseTableName = "pageElement"

    public var id: Int64?
    public var pageId: Int64
    public var postId: Int64
    public var position: Int64

    public init(
        id: Int64? = nil,
        pageId: Int64,
        postId: Int64,
        position: Int64
    ) {
        self.id = id
        self.pageId = pageId
        self.postId = postId
        self.position = position
    }
}

extension PageElementRecord: FetchableRecord, MutablePersistableRecord {
    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
