//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

public struct CommentRecord: Codable, Sendable, Equatable, Identifiable {
    public static let databaseTableName = "comment"

    public var id: Int64?
    public var postId: Int64
    public var creatorId: Int64
    public var localCommentId: Int64
    public var body: String
    public var score: Int64
    public var numberOfUpvotes: Int64
    public var numberOfDownvotes: Int64
    /// 1 = upvote, 0 = downvote, nil = no vote.
    public var voteStatus: Int64?
    public var originalCommentUrl: String?
    public var published: Date
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: Int64? = nil,
        postId: Int64,
        creatorId: Int64,
        localCommentId: Int64,
        body: String,
        score: Int64 = 0,
        numberOfUpvotes: Int64 = 0,
        numberOfDownvotes: Int64 = 0,
        voteStatus: Int64? = nil,
        originalCommentUrl: String? = nil,
        published: Date,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.postId = postId
        self.creatorId = creatorId
        self.localCommentId = localCommentId
        self.body = body
        self.score = score
        self.numberOfUpvotes = numberOfUpvotes
        self.numberOfDownvotes = numberOfDownvotes
        self.voteStatus = voteStatus
        self.originalCommentUrl = originalCommentUrl
        self.published = published
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension CommentRecord: FetchableRecord, MutablePersistableRecord {
    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public struct CommentElementRecord: Codable, Sendable, Equatable, Identifiable {
    public static let databaseTableName = "commentElement"

    public var id: Int64?
    public var postId: Int64
    /// nil for "load more" placeholder rows that have no backing comment.
    public var commentId: Int64?
    public var position: Int64
    public var depth: Int64
    public var sortType: String
    public var moreChildCount: Int64?
    public var moreParentId: Int64?

    public init(
        id: Int64? = nil,
        postId: Int64,
        commentId: Int64? = nil,
        position: Int64,
        depth: Int64 = 0,
        sortType: String,
        moreChildCount: Int64? = nil,
        moreParentId: Int64? = nil
    ) {
        self.id = id
        self.postId = postId
        self.commentId = commentId
        self.position = position
        self.depth = depth
        self.sortType = sortType
        self.moreChildCount = moreChildCount
        self.moreParentId = moreParentId
    }
}

extension CommentElementRecord: FetchableRecord, MutablePersistableRecord {
    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
