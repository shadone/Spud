//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import OSLog

private let logger = Logger.appDatabase

/// Composite snapshot row for the PostDetail header. Joins post + community
/// + creator + creator's site/instance so the header cell can render without
/// further lookups.
public struct PostDetailHeaderRow: Sendable, Equatable, Identifiable {
    public let id: Int64
    public let serverPostId: Int64
    public let title: String
    public let body: String?
    /// The post's federation permalink (`post.ap_id`), e.g.
    /// "https://lemmy.world/post/123". The canonical URL to share.
    public let originalPostUrl: String
    public let url: String?
    public let thumbnailUrl: String?
    /// Pixel dimensions of the post's image (`PostView.image_details`), when the
    /// instance reports them. Lets the header reserve the image's height before
    /// it loads. nil when unknown.
    public let imageWidth: Int?
    public let imageHeight: Int?
    public let urlEmbedTitle: String?
    public let urlEmbedDescription: String?
    /// Optional image description (`post.alt_text`), shown as the media-viewer
    /// caption when the header image is opened full-screen.
    public let altText: String?
    public let communityName: String
    /// The community's display name (`community.title`), shown in the post-detail
    /// header attribution. nil/empty falls back to `communityName`.
    public let communityTitle: String?
    /// The community's federation actor id (e.g.
    /// "https://lemmy.world/c/world"). Used to derive the home instance for a
    /// community deep link. nil if the community row has no actorId.
    public let communityActorId: String?
    /// Server-assigned community id. Used to gate moderation actions (and to
    /// scope ban-from-community on comments under this post) against the set
    /// of communities the current account moderates.
    public let serverCommunityId: Int64
    public let creatorName: String
    public let creatorPersonId: Int64
    public let creatorInstanceActorId: String
    public let score: Int64
    public let numberOfComments: Int64
    /// 1 = upvoted, 0 = downvoted, nil = no vote.
    public let voteStatus: Int64?
    public let isSaved: Bool
    /// Moderation / content-status flags driving the status badges.
    public let isRemoved: Bool
    public let isLocked: Bool
    public let isFeaturedCommunity: Bool
    public let isFeaturedLocal: Bool
    public let isDeleted: Bool
    /// True when the post or its community is marked as NSFW. Drives the
    /// blur overlay in the header cell when the "blur NSFW" preference is on.
    public let isNsfw: Bool
    public let published: Date

    public init(
        id: Int64,
        serverPostId: Int64,
        title: String,
        body: String?,
        originalPostUrl: String,
        url: String?,
        thumbnailUrl: String?,
        imageWidth: Int?,
        imageHeight: Int?,
        urlEmbedTitle: String?,
        urlEmbedDescription: String?,
        altText: String?,
        communityName: String,
        communityTitle: String? = nil,
        communityActorId: String?,
        serverCommunityId: Int64,
        creatorName: String,
        creatorPersonId: Int64,
        creatorInstanceActorId: String,
        score: Int64,
        numberOfComments: Int64,
        voteStatus: Int64?,
        isSaved: Bool,
        isRemoved: Bool,
        isLocked: Bool,
        isFeaturedCommunity: Bool,
        isFeaturedLocal: Bool,
        isDeleted: Bool,
        isNsfw: Bool,
        published: Date
    ) {
        self.id = id
        self.serverPostId = serverPostId
        self.title = title
        self.body = body
        self.originalPostUrl = originalPostUrl
        self.url = url
        self.thumbnailUrl = thumbnailUrl
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.urlEmbedTitle = urlEmbedTitle
        self.urlEmbedDescription = urlEmbedDescription
        self.altText = altText
        self.communityName = communityName
        self.communityTitle = communityTitle
        self.communityActorId = communityActorId
        self.serverCommunityId = serverCommunityId
        self.creatorName = creatorName
        self.creatorPersonId = creatorPersonId
        self.creatorInstanceActorId = creatorInstanceActorId
        self.score = score
        self.numberOfComments = numberOfComments
        self.voteStatus = voteStatus
        self.isSaved = isSaved
        self.isRemoved = isRemoved
        self.isLocked = isLocked
        self.isFeaturedCommunity = isFeaturedCommunity
        self.isFeaturedLocal = isFeaturedLocal
        self.isDeleted = isDeleted
        self.isNsfw = isNsfw
        self.published = published
    }
}

/// Composite snapshot row for one entry in the comment tree. Carries
/// element ordering metadata, the underlying comment fields when present,
/// and the creator's name + person id + instance actor id used to build
/// SpudInternalLink urls in author labels.
public struct PostDetailCommentRow: Sendable, Equatable, Identifiable {
    public let id: Int64
    public let position: Int64
    public let depth: Int64
    /// Server-assigned comment id (`CommentRecord.localCommentId`). nil for
    /// "load more" placeholders.
    public let serverCommentId: Int64?
    public let body: String?
    /// The comment's federation permalink (`comment.ap_id`), e.g.
    /// "https://lemmy.world/comment/456". The canonical URL to share. nil for
    /// "load more" placeholders.
    public let originalCommentUrl: String?
    public let score: Int64
    /// 1 = upvoted, 0 = downvoted, nil = no vote.
    public let voteStatus: Int64?
    /// nil for "load more" placeholders.
    public let isSaved: Bool?
    /// Moderation / content-status flags driving the status badges. nil for
    /// "load more" placeholders.
    public let isRemoved: Bool?
    public let isDistinguished: Bool?
    public let isDeleted: Bool?
    /// Per-comment creator context (`CommentView`) and creator-account flags
    /// (`Person`) driving the badge row and name treatment. nil for "load
    /// more" placeholders.
    public let isCreatorModerator: Bool?
    public let isCreatorAdmin: Bool?
    public let isCreatorBannedFromCommunity: Bool?
    public let isCreatorBlocked: Bool?
    public let isCreatorSiteBanned: Bool?
    public let isCreatorBot: Bool?
    public let isCreatorAccountDeleted: Bool?
    /// Moderator removal reason (mirrored from the modlog), shown on a
    /// removed comment's placeholder. nil when absent.
    public let removedReason: String?
    public let published: Date?
    public let creatorName: String?
    public let creatorPersonId: Int64?
    public let creatorInstanceActorId: String?
    /// For "load more" placeholders, the number of children waiting and
    /// the parent comment id. Both nil for normal rows.
    public let moreChildCount: Int64?
    public let moreParentId: Int64?

    public init(
        id: Int64,
        position: Int64,
        depth: Int64,
        serverCommentId: Int64?,
        body: String?,
        originalCommentUrl: String?,
        score: Int64,
        voteStatus: Int64?,
        isSaved: Bool?,
        isRemoved: Bool?,
        isDistinguished: Bool?,
        isDeleted: Bool?,
        isCreatorModerator: Bool?,
        isCreatorAdmin: Bool?,
        isCreatorBannedFromCommunity: Bool?,
        isCreatorBlocked: Bool?,
        isCreatorSiteBanned: Bool?,
        isCreatorBot: Bool?,
        isCreatorAccountDeleted: Bool?,
        removedReason: String?,
        published: Date?,
        creatorName: String?,
        creatorPersonId: Int64?,
        creatorInstanceActorId: String?,
        moreChildCount: Int64?,
        moreParentId: Int64?
    ) {
        self.id = id
        self.position = position
        self.depth = depth
        self.serverCommentId = serverCommentId
        self.body = body
        self.originalCommentUrl = originalCommentUrl
        self.score = score
        self.voteStatus = voteStatus
        self.isSaved = isSaved
        self.isRemoved = isRemoved
        self.isDistinguished = isDistinguished
        self.isDeleted = isDeleted
        self.isCreatorModerator = isCreatorModerator
        self.isCreatorAdmin = isCreatorAdmin
        self.isCreatorBannedFromCommunity = isCreatorBannedFromCommunity
        self.isCreatorBlocked = isCreatorBlocked
        self.isCreatorSiteBanned = isCreatorSiteBanned
        self.isCreatorBot = isCreatorBot
        self.isCreatorAccountDeleted = isCreatorAccountDeleted
        self.removedReason = removedReason
        self.published = published
        self.creatorName = creatorName
        self.creatorPersonId = creatorPersonId
        self.creatorInstanceActorId = creatorInstanceActorId
        self.moreChildCount = moreChildCount
        self.moreParentId = moreParentId
    }
}

public extension AppDatabase {
    /// Resolves the row id of a post by `(accountKeychainId, serverPostId)`.
    /// Synchronous to keep view-controller bring-up paths simple.
    func postRowIdSync(forKeychainId keychainId: String, serverPostId: Int64) -> Int64? {
        do {
            return try writer.read { db in
                let accountId: Int64? = try AccountRecord
                    .filter(Column("accountKeychainId") == keychainId)
                    .fetchOne(db)?
                    .id
                guard let accountId else { return nil }
                return try PostRecord
                    .filter(Column("accountId") == accountId)
                    .filter(Column("postId") == serverPostId)
                    .fetchOne(db)?
                    .id
            }
        } catch {
            logger.error("Failed to resolve post row id: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Stream of the PostDetail header row for `postRowId`. Yields nil if the
    /// post row no longer exists.
    func observePostDetailHeader(postRowId: Int64) -> AsyncStream<PostDetailHeaderRow?> {
        let observation = ValueObservation
            .tracking { db -> PostDetailHeaderRow? in
                guard let row = try Row.fetchOne(db, sql: """
                        SELECT
                            post.id                    AS postRowId,
                            post.postId                AS serverPostId,
                            post.title                 AS title,
                            post.body                  AS body,
                            post.originalPostUrl       AS originalPostUrl,
                            post.url                   AS url,
                            post.thumbnailUrl          AS thumbnailUrl,
                            post.imageWidth            AS imageWidth,
                            post.imageHeight           AS imageHeight,
                            post.urlEmbedTitle         AS urlEmbedTitle,
                            post.urlEmbedDescription   AS urlEmbedDescription,
                            post.altText               AS altText,
                            post.score                 AS score,
                            post.numberOfComments      AS numberOfComments,
                            post.voteStatus            AS voteStatus,
                            post.isSaved               AS isSaved,
                            post.isRemoved             AS isRemoved,
                            post.isLocked              AS isLocked,
                            post.isFeaturedCommunity   AS isFeaturedCommunity,
                            post.isFeaturedLocal       AS isFeaturedLocal,
                            post.isDeleted             AS isDeleted,
                            (post.isNsfw OR community.isNsfw) AS isNsfw,
                            post.published             AS published,
                            community.communityId      AS serverCommunityId,
                            community.name             AS communityName,
                            community.title            AS communityTitle,
                            community.actorId          AS communityActorId,
                            creator.name               AS creatorName,
                            creator.displayName        AS creatorDisplayName,
                            creator.personId           AS creatorPersonId,
                            creatorInstance.actorId    AS creatorInstanceActorId
                        FROM post
                        JOIN community  ON community.id = post.communityId
                        JOIN person     AS creator         ON creator.id = post.creatorId
                        JOIN site       AS creatorSite     ON creatorSite.id = creator.siteId
                        JOIN instance   AS creatorInstance ON creatorInstance.id = creatorSite.instanceId
                        WHERE post.id = ?
                    """, arguments: [postRowId])
                else {
                    return nil
                }

                let rawCreatorName = row.coalescingString("creatorDisplayName", "creatorName")
                return PostDetailHeaderRow(
                    id: row["postRowId"],
                    serverPostId: row["serverPostId"],
                    title: row["title"],
                    body: row["body"],
                    originalPostUrl: row["originalPostUrl"] ?? "",
                    url: row["url"],
                    thumbnailUrl: row["thumbnailUrl"],
                    imageWidth: row["imageWidth"],
                    imageHeight: row["imageHeight"],
                    urlEmbedTitle: row["urlEmbedTitle"],
                    urlEmbedDescription: row["urlEmbedDescription"],
                    altText: row["altText"],
                    communityName: row["communityName"] ?? "",
                    communityTitle: row["communityTitle"],
                    communityActorId: row["communityActorId"],
                    serverCommunityId: row["serverCommunityId"],
                    creatorName: rawCreatorName ?? "",
                    creatorPersonId: row["creatorPersonId"],
                    creatorInstanceActorId: row["creatorInstanceActorId"],
                    score: row["score"],
                    numberOfComments: row["numberOfComments"],
                    voteStatus: row["voteStatus"],
                    isSaved: row["isSaved"],
                    isRemoved: row["isRemoved"],
                    isLocked: row["isLocked"],
                    isFeaturedCommunity: row["isFeaturedCommunity"],
                    isFeaturedLocal: row["isFeaturedLocal"],
                    isDeleted: row["isDeleted"],
                    isNsfw: row["isNsfw"],
                    published: row["published"]
                )
            }
            .removeDuplicates()

        return AsyncStream { continuation in
            let cancellable = observation.start(in: writer, scheduling: .async(onQueue: .global(qos: .userInitiated))) { error in
                logger.error("PostDetailHeader observation failed: \(String(describing: error), privacy: .public)")
                continuation.finish()
            } onChange: { value in
                continuation.yield(value)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    /// Stream of comment-tree rows for `(postRowId, sortType)`, in display
    /// order. Joins the comment element + comment + creator + creator's
    /// site/instance so the cell can render without further lookups.
    func observePostDetailComments(
        postRowId: Int64,
        sortType: String
    ) -> AsyncStream<[PostDetailCommentRow]> {
        let observation = ValueObservation
            .tracking { db -> [PostDetailCommentRow] in
                let rows = try Row.fetchAll(db, sql: """
                        SELECT
                            commentElement.id              AS elementId,
                            commentElement.position        AS position,
                            commentElement.depth           AS depth,
                            commentElement.moreChildCount  AS moreChildCount,
                            commentElement.moreParentId    AS moreParentId,
                            comment.localCommentId         AS serverCommentId,
                            comment.body                   AS body,
                            comment.originalCommentUrl     AS originalCommentUrl,
                            comment.score                  AS score,
                            comment.voteStatus             AS voteStatus,
                            comment.isSaved                AS isSaved,
                            comment.isRemoved              AS isRemoved,
                            comment.isDistinguished        AS isDistinguished,
                            comment.isDeleted              AS isDeleted,
                            comment.isCreatorModerator     AS isCreatorModerator,
                            comment.isCreatorAdmin         AS isCreatorAdmin,
                            comment.isCreatorBannedFromCommunity AS isCreatorBannedFromCommunity,
                            comment.isCreatorBlocked       AS isCreatorBlocked,
                            comment.removedReason          AS removedReason,
                            comment.published              AS published,
                            creator.name                   AS creatorName,
                            creator.displayName            AS creatorDisplayName,
                            creator.personId               AS creatorPersonId,
                            creator.isBanned               AS creatorIsSiteBanned,
                            creator.isBotAccount           AS creatorIsBot,
                            creator.isDeleted              AS creatorAccountDeleted,
                            creatorInstance.actorId        AS creatorInstanceActorId
                        FROM commentElement
                        LEFT JOIN comment ON comment.id = commentElement.commentId
                        LEFT JOIN person     AS creator         ON creator.id = comment.creatorId
                        LEFT JOIN site       AS creatorSite     ON creatorSite.id = creator.siteId
                        LEFT JOIN instance   AS creatorInstance ON creatorInstance.id = creatorSite.instanceId
                        WHERE commentElement.postId = ?
                          AND commentElement.sortType = ?
                        ORDER BY commentElement.position ASC
                    """, arguments: [postRowId, sortType])

                return rows.map { row in
                    let rawCreatorName = row.coalescingString("creatorDisplayName", "creatorName")
                    return PostDetailCommentRow(
                        id: row["elementId"],
                        position: row["position"],
                        depth: row["depth"],
                        serverCommentId: row["serverCommentId"],
                        body: row["body"],
                        originalCommentUrl: row["originalCommentUrl"],
                        score: row["score"] ?? 0,
                        voteStatus: row["voteStatus"],
                        isSaved: row["isSaved"],
                        isRemoved: row["isRemoved"],
                        isDistinguished: row["isDistinguished"],
                        isDeleted: row["isDeleted"],
                        isCreatorModerator: row["isCreatorModerator"],
                        isCreatorAdmin: row["isCreatorAdmin"],
                        isCreatorBannedFromCommunity: row["isCreatorBannedFromCommunity"],
                        isCreatorBlocked: row["isCreatorBlocked"],
                        isCreatorSiteBanned: row["creatorIsSiteBanned"],
                        isCreatorBot: row["creatorIsBot"],
                        isCreatorAccountDeleted: row["creatorAccountDeleted"],
                        removedReason: row["removedReason"],
                        published: row["published"],
                        creatorName: rawCreatorName,
                        creatorPersonId: row["creatorPersonId"],
                        creatorInstanceActorId: row["creatorInstanceActorId"],
                        moreChildCount: row["moreChildCount"],
                        moreParentId: row["moreParentId"]
                    )
                }
            }
            .removeDuplicates()

        return AsyncStream { continuation in
            let cancellable = observation.start(in: writer, scheduling: .async(onQueue: .global(qos: .userInitiated))) { error in
                logger.error("PostDetailComments observation failed: \(String(describing: error), privacy: .public)")
                continuation.finish()
            } onChange: { value in
                continuation.yield(value)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }
}
