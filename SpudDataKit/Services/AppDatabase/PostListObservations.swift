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
    public let communityName: String
    /// The community's federation actor id (e.g.
    /// "https://lemmy.world/c/world"). Used to derive the home instance for a
    /// community deep link. nil if the community row has no actorId.
    public let communityActorId: String?
    public let score: Int64
    public let numberOfComments: Int64
    /// 1 = upvoted, 0 = downvoted, nil = no vote.
    public let voteStatus: Int64?
    public let isRead: Bool
    public let isSaved: Bool
    public let published: Date
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
                            post.score             AS score,
                            post.numberOfComments  AS numberOfComments,
                            post.voteStatus        AS voteStatus,
                            post.isRead            AS isRead,
                            post.isSaved           AS isSaved,
                            post.published         AS published,
                            community.name         AS communityName,
                            community.actorId      AS communityActorId
                        FROM post
                        JOIN pageElement ON pageElement.postId = post.id
                        JOIN page        ON page.id = pageElement.pageId
                        JOIN community   ON community.id = post.communityId
                        WHERE page.feedId = ?
                        ORDER BY page.position ASC, pageElement.position ASC
                    """, arguments: [feedId])

                return rows.map { row in
                    PostListRow(
                        id: row["postRowId"],
                        serverPostId: row["serverPostId"],
                        title: row["title"],
                        body: row["body"],
                        originalPostUrl: row["originalPostUrl"] ?? "",
                        url: row["url"],
                        thumbnailUrl: row["thumbnailUrl"],
                        urlEmbedTitle: row["urlEmbedTitle"],
                        urlEmbedDescription: row["urlEmbedDescription"],
                        communityName: row["communityName"] ?? "",
                        communityActorId: row["communityActorId"],
                        score: row["score"],
                        numberOfComments: row["numberOfComments"],
                        voteStatus: row["voteStatus"],
                        isRead: row["isRead"],
                        isSaved: row["isSaved"],
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
