//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

/// Caller-provided render snapshot for a post interaction. Denormalized onto
/// the interaction row so history renders and searches without joining the
/// (possibly-evicted) `post` cache.
public struct PostInteractionSnapshot: Sendable, Equatable {
    public let titleSnapshot: String
    public let communityName: String
    public let instanceHost: String
    public let thumbnailUrl: String?
    public let author: String?

    public init(
        titleSnapshot: String,
        communityName: String,
        instanceHost: String,
        thumbnailUrl: String?,
        author: String?
    ) {
        self.titleSnapshot = titleSnapshot
        self.communityName = communityName
        self.instanceHost = instanceHost
        self.thumbnailUrl = thumbnailUrl
        self.author = author
    }
}

/// Local-only interaction log row. Records, per `(accountId, postServerId)`,
/// when a post was first/last seen on screen and last opened, plus a render
/// snapshot. Never synced to or mirrored from the server. `postServerId` is a
/// plain integer (not a foreign key) so a row survives `post` cache eviction.
public struct PostInteractionRecord: Codable, Sendable, Equatable, Identifiable {
    public static let databaseTableName = "postInteraction"

    public var id: Int64?
    public var accountId: Int64
    public var postServerId: Int64
    public var titleSnapshot: String?
    public var communityName: String?
    public var instanceHost: String?
    public var thumbnailUrl: String?
    public var author: String?
    public var firstSeenAt: Date?
    public var lastSeenAt: Date?
    public var seenCount: Int
    public var lastOpenedAt: Date?
    public var openedCount: Int
    public var lastKnownCommentCount: Int64?

    public init(
        id: Int64? = nil,
        accountId: Int64,
        postServerId: Int64,
        titleSnapshot: String? = nil,
        communityName: String? = nil,
        instanceHost: String? = nil,
        thumbnailUrl: String? = nil,
        author: String? = nil,
        firstSeenAt: Date? = nil,
        lastSeenAt: Date? = nil,
        seenCount: Int = 0,
        lastOpenedAt: Date? = nil,
        openedCount: Int = 0,
        lastKnownCommentCount: Int64? = nil
    ) {
        self.id = id
        self.accountId = accountId
        self.postServerId = postServerId
        self.titleSnapshot = titleSnapshot
        self.communityName = communityName
        self.instanceHost = instanceHost
        self.thumbnailUrl = thumbnailUrl
        self.author = author
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
        self.seenCount = seenCount
        self.lastOpenedAt = lastOpenedAt
        self.openedCount = openedCount
        self.lastKnownCommentCount = lastKnownCommentCount
    }

    /// Overwrites the denormalized snapshot fields from `snapshot`.
    public mutating func apply(_ snapshot: PostInteractionSnapshot) {
        titleSnapshot = snapshot.titleSnapshot
        communityName = snapshot.communityName
        instanceHost = snapshot.instanceHost
        thumbnailUrl = snapshot.thumbnailUrl
        author = snapshot.author
    }
}

extension PostInteractionRecord: FetchableRecord, MutablePersistableRecord {
    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
