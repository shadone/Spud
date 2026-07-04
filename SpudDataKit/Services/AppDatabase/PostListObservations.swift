//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import OSLog

private let logger = Logger.appDatabase

/// Composite snapshot row for the PostList screen. Joins post + community
/// so the cell can render without further lookups. Vote/score/comment counts
/// come from the post row directly.
public struct PostListRow: Sendable, Equatable, Identifiable {
    public let id: Int64
    /// Server-assigned post id (`PostRecord.postId`).
    public let serverPostId: Int64
    public let title: String
    public let body: String?
    /// The post's federation permalink (`post.ap_id`). The canonical URL to
    /// share.
    public let originalPostUrl: String
    public let url: String?
    public let thumbnailUrl: String?
    public let urlEmbedTitle: String?
    public let urlEmbedDescription: String?
    /// Optional image description (`post.alt_text`), shown as the media-viewer
    /// caption when the post's image is opened full-screen.
    public let altText: String?
    public let communityName: String
    /// The community's federation actor id (e.g.
    /// "https://lemmy.world/c/world"). Used to derive the home instance for a
    /// community deep link. nil if the community row has no actorId.
    public let communityActorId: String?
    /// Server-assigned community id. Used to gate moderation actions against
    /// the set of communities the current account moderates.
    public let serverCommunityId: Int64
    /// Server-assigned creator (post author) person id. Used to target
    /// ban-from-community actions and to deep link to the author.
    public let creatorPersonId: Int64
    /// The author's handle (`person.name`, e.g. "alice"). Used to label the
    /// "View u/..." context-menu action. nil if the person row has no name.
    public let creatorName: String?
    /// The author's federation actor id (e.g. "https://lemmy.world/u/alice").
    /// Used to derive the home instance for an author deep link. nil if the
    /// person row has no actorId.
    public let creatorActorId: String?
    public let score: Int64
    public let numberOfComments: Int64
    /// 1 = upvoted, 0 = downvoted, nil = no vote.
    public let voteStatus: Int64?
    public let isRead: Bool
    public let isSaved: Bool
    /// Moderation / content-status flags driving the status badges.
    public let isRemoved: Bool
    public let isLocked: Bool
    public let isFeaturedCommunity: Bool
    public let isFeaturedLocal: Bool
    public let isDeleted: Bool
    /// True when the server returned `couldnt_find_post` (or any equivalent
    /// "post not found" error) for this post. The post is gone — removed,
    /// deleted, or de-federated — but the exact reason is unknown. Drives the
    /// neutral unavailable badge rather than a red removed/deleted badge.
    public let isUnavailable: Bool
    /// Whether the post or its community is marked NSFW. Drives blur-on-display.
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
        urlEmbedTitle: String?,
        urlEmbedDescription: String?,
        altText: String?,
        communityName: String,
        communityActorId: String?,
        serverCommunityId: Int64,
        creatorPersonId: Int64,
        creatorName: String?,
        creatorActorId: String?,
        score: Int64,
        numberOfComments: Int64,
        voteStatus: Int64?,
        isRead: Bool,
        isSaved: Bool,
        isRemoved: Bool,
        isLocked: Bool,
        isFeaturedCommunity: Bool,
        isFeaturedLocal: Bool,
        isDeleted: Bool,
        isUnavailable: Bool = false,
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
        self.urlEmbedTitle = urlEmbedTitle
        self.urlEmbedDescription = urlEmbedDescription
        self.altText = altText
        self.communityName = communityName
        self.communityActorId = communityActorId
        self.serverCommunityId = serverCommunityId
        self.creatorPersonId = creatorPersonId
        self.creatorName = creatorName
        self.creatorActorId = creatorActorId
        self.score = score
        self.numberOfComments = numberOfComments
        self.voteStatus = voteStatus
        self.isRead = isRead
        self.isSaved = isSaved
        self.isRemoved = isRemoved
        self.isLocked = isLocked
        self.isFeaturedCommunity = isFeaturedCommunity
        self.isFeaturedLocal = isFeaturedLocal
        self.isDeleted = isDeleted
        self.isUnavailable = isUnavailable
        self.isNsfw = isNsfw
        self.published = published
    }
}

public extension AppDatabase {
    /// Resolves the row id of a feed by its `feedKey`. Synchronous to keep
    /// view-controller bring-up paths simple. Returns nil before the first
    /// `appendFeedPage` lazily creates the row.
    func feedRowIdSync(forFeedKey feedKey: String) -> Int64? {
        do {
            return try writer.read { db in
                try FeedRecord
                    .filter(Column("feedKey") == feedKey)
                    .fetchOne(db)?
                    .id
            }
        } catch {
            logger.error("Failed to resolve feed row id: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Stream of PostList rows for a feed in display order
    /// (page.position, pageElement.position).
    func observePostListRows(feedId: Int64) -> AsyncStream<[PostListRow]> {
        let observation = ValueObservation
            .tracking { db -> [PostListRow] in
                let rows = try Row.fetchAll(db, sql: """
                        SELECT
                            post.id                AS postRowId,
                            post.postId            AS serverPostId,
                            post.title             AS title,
                            post.body              AS body,
                            post.originalPostUrl   AS originalPostUrl,
                            post.url               AS url,
                            post.thumbnailUrl      AS thumbnailUrl,
                            post.urlEmbedTitle     AS urlEmbedTitle,
                            post.urlEmbedDescription AS urlEmbedDescription,
                            post.altText           AS altText,
                            post.score             AS score,
                            post.numberOfComments  AS numberOfComments,
                            post.voteStatus        AS voteStatus,
                            post.isRead            AS isRead,
                            post.isSaved           AS isSaved,
                            post.isRemoved         AS isRemoved,
                            post.isLocked          AS isLocked,
                            post.isFeaturedCommunity AS isFeaturedCommunity,
                            post.isFeaturedLocal   AS isFeaturedLocal,
                            post.isDeleted         AS isDeleted,
                            post.isUnavailable     AS isUnavailable,
                            (post.isNsfw OR community.isNsfw) AS isNsfw,
                            post.published         AS published,
                            community.communityId  AS serverCommunityId,
                            community.name         AS communityName,
                            community.actorId      AS communityActorId,
                            creator.personId       AS creatorPersonId,
                            creator.name           AS creatorName,
                            creator.actorId        AS creatorActorId
                        FROM post
                        JOIN pageElement ON pageElement.postId = post.id
                        JOIN page        ON page.id = pageElement.pageId
                        JOIN community   ON community.id = post.communityId
                        JOIN person      AS creator ON creator.id = post.creatorId
                        WHERE page.feedId = ?
                          AND post.isHidden = 0
                        ORDER BY page.position ASC, pageElement.position ASC
                    """, arguments: [feedId])

                // Drop posts from communities the account has muted (a
                // client-side, timed view concern). Reading the mute table here
                // adds it to the observation region, so muting/unmuting
                // re-emits the feed.
                let mutedActorIds = try Self.activeMutedCommunityActorIds(db, feedId: feedId)

                return rows.compactMap { row -> PostListRow? in
                    let communityActorId: String? = row["communityActorId"]
                    if let communityActorId, mutedActorIds.contains(communityActorId) {
                        return nil
                    }
                    return PostListRow(
                        id: row["postRowId"],
                        serverPostId: row["serverPostId"],
                        title: row["title"],
                        body: row["body"],
                        originalPostUrl: row["originalPostUrl"] ?? "",
                        url: row["url"],
                        thumbnailUrl: row["thumbnailUrl"],
                        urlEmbedTitle: row["urlEmbedTitle"],
                        urlEmbedDescription: row["urlEmbedDescription"],
                        altText: row["altText"],
                        communityName: row["communityName"] ?? "",
                        communityActorId: row["communityActorId"],
                        serverCommunityId: row["serverCommunityId"],
                        creatorPersonId: row["creatorPersonId"],
                        creatorName: row["creatorName"],
                        creatorActorId: row["creatorActorId"],
                        score: row["score"],
                        numberOfComments: row["numberOfComments"],
                        voteStatus: row["voteStatus"],
                        isRead: row["isRead"],
                        isSaved: row["isSaved"],
                        isRemoved: row["isRemoved"],
                        isLocked: row["isLocked"],
                        isFeaturedCommunity: row["isFeaturedCommunity"],
                        isFeaturedLocal: row["isFeaturedLocal"],
                        isDeleted: row["isDeleted"],
                        isUnavailable: row["isUnavailable"],
                        isNsfw: row["isNsfw"],
                        published: row["published"]
                    )
                }
            }
            .removeDuplicates()

        return AsyncStream { continuation in
            let cancellable = observation.start(in: writer, scheduling: .async(onQueue: .global(qos: .userInitiated))) { error in
                logger.error("PostList ValueObservation failed: \(String(describing: error), privacy: .public)")
                continuation.finish()
            } onChange: { value in
                continuation.yield(value)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }
}
