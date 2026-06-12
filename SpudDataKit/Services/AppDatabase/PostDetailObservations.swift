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
    public let urlEmbedTitle: String?
    public let urlEmbedDescription: String?
    public let communityName: String
    /// The community's federation actor id (e.g.
    /// "https://lemmy.world/c/world"). Used to derive the home instance for a
    /// community deep link. nil if the community row has no actorId.
    public let communityActorId: String?
    public let creatorName: String
    public let creatorPersonId: Int64
    public let creatorInstanceActorId: String
    public let score: Int64
    public let numberOfComments: Int64
    /// 1 = upvoted, 0 = downvoted, nil = no vote.
    public let voteStatus: Int64?
    public let isSaved: Bool
    public let published: Date
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
    public let published: Date?
    public let creatorName: String?
    public let creatorPersonId: Int64?
    public let creatorInstanceActorId: String?
    /// For "load more" placeholders, the number of children waiting and
    /// the parent comment id. Both nil for normal rows.
    public let moreChildCount: Int64?
    public let moreParentId: Int64?
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
                            post.urlEmbedTitle         AS urlEmbedTitle,
                            post.urlEmbedDescription   AS urlEmbedDescription,
                            post.score                 AS score,
                            post.numberOfComments      AS numberOfComments,
                            post.voteStatus            AS voteStatus,
                            post.isSaved               AS isSaved,
                            post.published             AS published,
                            community.name             AS communityName,
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

                let rawCreatorName: String? = row["creatorDisplayName"] ?? row["creatorName"]
                return PostDetailHeaderRow(
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
                    creatorName: rawCreatorName ?? "",
                    creatorPersonId: row["creatorPersonId"],
                    creatorInstanceActorId: row["creatorInstanceActorId"],
                    score: row["score"],
                    numberOfComments: row["numberOfComments"],
                    voteStatus: row["voteStatus"],
                    isSaved: row["isSaved"],
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
                            comment.published              AS published,
                            creator.name                   AS creatorName,
                            creator.displayName            AS creatorDisplayName,
                            creator.personId               AS creatorPersonId,
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
                    let rawCreatorName: String? = row["creatorDisplayName"] ?? row["creatorName"]
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
