//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

/// A single forward-only log entry recording that the account voted on a post
/// or comment. One row per `(accountId, entityType, entityServerId)`; the row is
/// upserted on every vote change and deleted when the vote is removed or
/// permanently rolled back by the outbox.
///
/// Snapshot columns (`title`, `body`, `communityName`, etc.) are denormalized at
/// write time so the Activity timeline can render an entry even after the
/// originating `post`/`comment` cache row is evicted.
public struct VoteEventRecord: Codable, Sendable, Equatable, Identifiable {
    public static let databaseTableName = "voteEvent"

    public var id: Int64?
    public var accountId: Int64
    /// `"post"` or `"comment"`.
    public var entityType: String
    public var entityServerId: Int64
    /// 1 = upvote, 0 = downvote. Matches the existing `voteStatus` column convention.
    public var voteAction: Int64
    /// Unix epoch timestamp (seconds, sub-second precision). Sort key for the
    /// Activity timeline.
    public var votedAt: Double
    /// Post title (post votes) or parent post title (comment votes).
    public var title: String?
    /// Comment body; nil for post votes.
    public var body: String?
    public var communityName: String?
    public var communityActorId: String?
    public var thumbnailUrl: String?
    public var score: Int64?

    public init(
        id: Int64? = nil,
        accountId: Int64,
        entityType: String,
        entityServerId: Int64,
        voteAction: Int64,
        votedAt: Double,
        title: String? = nil,
        body: String? = nil,
        communityName: String? = nil,
        communityActorId: String? = nil,
        thumbnailUrl: String? = nil,
        score: Int64? = nil
    ) {
        self.id = id
        self.accountId = accountId
        self.entityType = entityType
        self.entityServerId = entityServerId
        self.voteAction = voteAction
        self.votedAt = votedAt
        self.title = title
        self.body = body
        self.communityName = communityName
        self.communityActorId = communityActorId
        self.thumbnailUrl = thumbnailUrl
        self.score = score
    }
}

extension VoteEventRecord: FetchableRecord, MutablePersistableRecord {
    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
