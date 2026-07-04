//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

public struct PostRecord: Codable, Sendable, Equatable, Identifiable {
    public static let databaseTableName = "post"

    public var id: Int64?
    public var accountId: Int64
    public var communityId: Int64
    public var creatorId: Int64
    public var postId: Int64
    public var title: String
    public var body: String?
    public var url: String?
    public var urlEmbedTitle: String?
    public var urlEmbedDescription: String?
    public var thumbnailUrl: String?
    /// Pixel dimensions of the post's image (`PostView.image_details`), when the
    /// instance reports them. Used to reserve the right amount of space for the
    /// image before it loads. nil when unknown.
    public var imageWidth: Int?
    public var imageHeight: Int?
    /// An optional image description (`post.alt_text`), surfaced as the caption
    /// in the full-screen media viewer.
    public var altText: String?
    public var originalPostUrl: String
    public var score: Int64
    public var numberOfUpvotes: Int64
    public var numberOfDownvotes: Int64
    public var numberOfComments: Int64
    public var isRead: Bool
    public var isSaved: Bool
    /// Whether the user hid this post (`PostView.hidden`). Hidden posts are
    /// filtered out of the feed list.
    public var isHidden: Bool
    /// Whether the post is marked not-safe-for-work (`PostView.post.nsfw`).
    /// Drives blur-on-display; the client did not record this before blur.
    public var isNsfw: Bool
    /// 1 = upvote, 0 = downvote, nil = no vote.
    public var voteStatus: Int64?
    /// Moderation / content-status flags mirrored from the Lemmy post object.
    public var isRemoved: Bool
    public var isLocked: Bool
    public var isFeaturedCommunity: Bool
    public var isFeaturedLocal: Bool
    public var isDeleted: Bool
    /// The server rejected a request for this post with `couldnt_find_post`
    /// (removed on its origin, author-deleted, or de-federated) while we still
    /// hold a stale cached copy. Distinct from `isRemoved`/`isDeleted`, which
    /// mean the server returned the post object and told us so; `isUnavailable`
    /// means we only know it is gone, not why. Cleared by a fresh PostView import.
    public var isUnavailable: Bool
    public var published: Date
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: Int64? = nil,
        accountId: Int64,
        communityId: Int64,
        creatorId: Int64,
        postId: Int64,
        title: String,
        body: String? = nil,
        url: String? = nil,
        urlEmbedTitle: String? = nil,
        urlEmbedDescription: String? = nil,
        thumbnailUrl: String? = nil,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        altText: String? = nil,
        originalPostUrl: String,
        score: Int64 = 0,
        numberOfUpvotes: Int64 = 0,
        numberOfDownvotes: Int64 = 0,
        numberOfComments: Int64 = 0,
        isRead: Bool = false,
        isSaved: Bool = false,
        isHidden: Bool = false,
        isNsfw: Bool = false,
        voteStatus: Int64? = nil,
        isRemoved: Bool = false,
        isLocked: Bool = false,
        isFeaturedCommunity: Bool = false,
        isFeaturedLocal: Bool = false,
        isDeleted: Bool = false,
        isUnavailable: Bool = false,
        published: Date,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.accountId = accountId
        self.communityId = communityId
        self.creatorId = creatorId
        self.postId = postId
        self.title = title
        self.body = body
        self.url = url
        self.urlEmbedTitle = urlEmbedTitle
        self.urlEmbedDescription = urlEmbedDescription
        self.thumbnailUrl = thumbnailUrl
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.altText = altText
        self.originalPostUrl = originalPostUrl
        self.score = score
        self.numberOfUpvotes = numberOfUpvotes
        self.numberOfDownvotes = numberOfDownvotes
        self.numberOfComments = numberOfComments
        self.isRead = isRead
        self.isSaved = isSaved
        self.isHidden = isHidden
        self.isNsfw = isNsfw
        self.voteStatus = voteStatus
        self.isRemoved = isRemoved
        self.isLocked = isLocked
        self.isFeaturedCommunity = isFeaturedCommunity
        self.isFeaturedLocal = isFeaturedLocal
        self.isDeleted = isDeleted
        self.isUnavailable = isUnavailable
        self.published = published
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension PostRecord: FetchableRecord, MutablePersistableRecord {
    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
