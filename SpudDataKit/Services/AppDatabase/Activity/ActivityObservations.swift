//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import OSLog

private let logger = Logger.appDatabase

/// Shared SELECT columns for PostListRow — requires `post`, `community`, and `creator` aliases in scope.
private let postListRowSQL = """
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
        (post.isNsfw OR community.isNsfw) AS isNsfw,
        post.published         AS published,
        community.communityId  AS serverCommunityId,
        community.name         AS communityName,
        community.actorId      AS communityActorId,
        creator.personId       AS creatorPersonId,
        creator.name           AS creatorName,
        creator.actorId        AS creatorActorId
    """

public extension AppDatabase {
    /// Unified reverse-chronological activity stream for one account.
    ///
    /// Each enabled `ActivityFilterType` contributes a separate DB query; results are merged
    /// in memory and sorted by `occurredAt` descending. `searchQuery` narrows post-based
    /// sources via FTS5; comment and voteEvent sources use a simple LIKE (v1 behaviour).
    func observeLocalActivity(
        accountId: Int64,
        filters: Set<ActivityFilterType>,
        searchQuery: String?
    ) -> AsyncStream<[ActivityItem]> {
        let trimmed = searchQuery?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveTrimmed: String? = (trimmed?.isEmpty ?? true) ? nil : trimmed

        let observation = ValueObservation
            .tracking { [filters, effectiveTrimmed, accountId] db -> [ActivityItem] in
                var items: [ActivityItem] = []
                if filters.contains(.read) {
                    items += try Self.fetchReadItems(db, accountId: accountId, search: effectiveTrimmed)
                }
                if filters.contains(.seen) {
                    items += try Self.fetchSeenItems(db, accountId: accountId, search: effectiveTrimmed)
                }
                if filters.contains(.save) {
                    items += try Self.fetchSavedPostItems(db, accountId: accountId, search: effectiveTrimmed)
                    items += try Self.fetchSavedCommentItems(db, accountId: accountId, search: effectiveTrimmed)
                }
                if filters.contains(.hide) {
                    items += try Self.fetchHiddenItems(db, accountId: accountId, search: effectiveTrimmed)
                }
                if filters.contains(.vote) {
                    items += try Self.fetchVotePostItems(db, accountId: accountId, search: effectiveTrimmed)
                    items += try Self.fetchVoteCommentItems(db, accountId: accountId, search: effectiveTrimmed)
                }
                return items.sorted { $0.occurredAt > $1.occurredAt }
            }
            .removeDuplicates()

        return AsyncStream { continuation in
            let cancellable = observation.start(
                in: writer,
                scheduling: .async(onQueue: .global(qos: .userInitiated))
            ) { error in
                logger.error("ActivityObservation failed: \(String(describing: error), privacy: .public)")
                continuation.finish()
            } onChange: { value in
                continuation.yield(value)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }
}

// MARK: - Per-source fetch helpers

private extension AppDatabase {
    static func postListRow(from row: Row) -> PostListRow {
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
            isNsfw: row["isNsfw"],
            published: row["published"]
        )
    }

    // MARK: Read

    static func fetchReadItems(_ db: Database, accountId: Int64, search: String?) throws -> [ActivityItem] {
        var sql = """
            SELECT \(postListRowSQL),
                   postInteraction.lastOpenedAt AS occurredAt
            FROM postInteraction
            JOIN post      ON post.accountId = postInteraction.accountId AND post.postId = postInteraction.postServerId
            JOIN community ON community.id = post.communityId
            JOIN person    AS creator ON creator.id = post.creatorId
            """
        var args: [any DatabaseValueConvertible] = []
        if let search, let pattern = FTS5Pattern(matchingAllTokensIn: search) {
            sql += "\nJOIN postInteractionFts ON postInteractionFts.rowid = postInteraction.id AND postInteractionFts MATCH ?"
            args.append(pattern)
        }
        sql += "\nWHERE postInteraction.accountId = ? AND postInteraction.lastOpenedAt IS NOT NULL"
        args.append(accountId)
        sql += "\nORDER BY postInteraction.lastOpenedAt DESC"

        return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args)).map { row in
            let postRow = postListRow(from: row)
            let occurredAt: Date = row["occurredAt"]
            return ActivityItem(
                id: "read-post-\(postRow.serverPostId)",
                act: .read,
                occurredAt: occurredAt,
                object: .post(postRow)
            )
        }
    }

    // MARK: Seen

    /// Read and Seen are mutually exclusive: a post with lastOpenedAt set is Read only.
    static func fetchSeenItems(_ db: Database, accountId: Int64, search: String?) throws -> [ActivityItem] {
        var sql = """
            SELECT \(postListRowSQL),
                   postInteraction.lastSeenAt AS occurredAt
            FROM postInteraction
            JOIN post      ON post.accountId = postInteraction.accountId AND post.postId = postInteraction.postServerId
            JOIN community ON community.id = post.communityId
            JOIN person    AS creator ON creator.id = post.creatorId
            """
        var args: [any DatabaseValueConvertible] = []
        if let search, let pattern = FTS5Pattern(matchingAllTokensIn: search) {
            sql += "\nJOIN postInteractionFts ON postInteractionFts.rowid = postInteraction.id AND postInteractionFts MATCH ?"
            args.append(pattern)
        }
        sql += "\nWHERE postInteraction.accountId = ? AND postInteraction.lastSeenAt IS NOT NULL AND postInteraction.lastOpenedAt IS NULL"
        args.append(accountId)
        sql += "\nORDER BY postInteraction.lastSeenAt DESC"

        return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args)).map { row in
            let postRow = postListRow(from: row)
            let occurredAt: Date = row["occurredAt"]
            return ActivityItem(
                id: "seen-post-\(postRow.serverPostId)",
                act: .seen,
                occurredAt: occurredAt,
                object: .post(postRow)
            )
        }
    }

    // MARK: Saved post

    /// Starts from `post` (not `postInteraction`) so saved posts with no interaction row are included.
    /// `occurredAt` is a Phase-1 proxy: coalesce(lastOpenedAt, lastSeenAt, post.published).
    /// Search uses LIKE on post.title (FTS not guaranteed for posts without an interaction row).
    static func fetchSavedPostItems(_ db: Database, accountId: Int64, search: String?) throws -> [ActivityItem] {
        var sql = """
            SELECT \(postListRowSQL),
                   coalesce(postInteraction.lastOpenedAt, postInteraction.lastSeenAt, post.published) AS occurredAt
            FROM post
            LEFT JOIN postInteraction ON postInteraction.accountId = post.accountId
                                     AND postInteraction.postServerId = post.postId
            JOIN community ON community.id = post.communityId
            JOIN person    AS creator ON creator.id = post.creatorId
            """
        var args: [any DatabaseValueConvertible] = []
        if let search {
            // v1: LIKE over post title (FTS requires an interaction row which may be absent)
            sql += "\nWHERE post.accountId = ? AND post.isSaved = 1 AND post.title LIKE ?"
            args.append(accountId)
            args.append("%\(search)%")
        } else {
            sql += "\nWHERE post.accountId = ? AND post.isSaved = 1"
            args.append(accountId)
        }
        sql += "\nORDER BY occurredAt DESC"

        return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args)).map { row in
            let postRow = postListRow(from: row)
            let occurredAt: Date = row["occurredAt"]
            return ActivityItem(
                id: "save-post-\(postRow.serverPostId)",
                act: .save,
                occurredAt: occurredAt,
                object: .post(postRow)
            )
        }
    }

    // MARK: Saved comment

    /// `occurredAt` = comment.published (no savedAt column; Phase-1 limitation).
    /// Search uses LIKE over comment body.
    static func fetchSavedCommentItems(_ db: Database, accountId: Int64, search: String?) throws -> [ActivityItem] {
        var sql = """
            SELECT
                comment.id             AS commentRowId,
                comment.localCommentId AS serverCommentId,
                comment.body           AS commentBody,
                comment.score          AS commentScore,
                comment.published      AS commentPublished,
                post.postId            AS parentServerPostId,
                post.title             AS parentPostTitle,
                community.name         AS communityName,
                community.actorId      AS communityActorId
            FROM comment
            JOIN post      ON post.id = comment.postId
            JOIN community ON community.id = post.communityId
            """
        var args: [any DatabaseValueConvertible] = []
        if let search {
            sql += "\nWHERE post.accountId = ? AND comment.isSaved = 1 AND comment.body LIKE ?"
            args.append(accountId)
            args.append("%\(search)%")
        } else {
            sql += "\nWHERE post.accountId = ? AND comment.isSaved = 1"
            args.append(accountId)
        }
        sql += "\nORDER BY comment.published DESC"

        return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args)).map { row in
            let published: Date = row["commentPublished"]
            let commentRow = ActivityCommentRow(
                id: row["commentRowId"],
                serverCommentId: row["serverCommentId"],
                body: row["commentBody"] ?? "",
                score: row["commentScore"] ?? 0,
                parentPostTitle: row["parentPostTitle"] ?? "",
                communityName: row["communityName"] ?? "",
                communityActorId: row["communityActorId"],
                serverPostId: row["parentServerPostId"],
                published: published
            )
            return ActivityItem(
                id: "save-comment-\(commentRow.serverCommentId)",
                act: .save,
                occurredAt: published,
                object: .comment(commentRow)
            )
        }
    }

    // MARK: Hidden post

    /// Phase-1 proxy for occurredAt: coalesce(lastOpenedAt, lastSeenAt, post.published).
    /// Search uses LIKE on post.title.
    static func fetchHiddenItems(_ db: Database, accountId: Int64, search: String?) throws -> [ActivityItem] {
        var sql = """
            SELECT \(postListRowSQL),
                   coalesce(postInteraction.lastOpenedAt, postInteraction.lastSeenAt, post.published) AS occurredAt
            FROM post
            LEFT JOIN postInteraction ON postInteraction.accountId = post.accountId
                                     AND postInteraction.postServerId = post.postId
            JOIN community ON community.id = post.communityId
            JOIN person    AS creator ON creator.id = post.creatorId
            """
        var args: [any DatabaseValueConvertible] = []
        if let search {
            sql += "\nWHERE post.accountId = ? AND post.isHidden = 1 AND post.title LIKE ?"
            args.append(accountId)
            args.append("%\(search)%")
        } else {
            sql += "\nWHERE post.accountId = ? AND post.isHidden = 1"
            args.append(accountId)
        }
        sql += "\nORDER BY occurredAt DESC"

        return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args)).map { row in
            let postRow = postListRow(from: row)
            let occurredAt: Date = row["occurredAt"]
            return ActivityItem(
                id: "hide-post-\(postRow.serverPostId)",
                act: .hide,
                occurredAt: occurredAt,
                object: .post(postRow)
            )
        }
    }

    // MARK: Vote (post)

    /// LEFT JOINs the live `post` row for enrichment; falls back to the voteEvent snapshot fields
    /// when the post has not been cached locally. `occurredAt` = voteEvent.votedAt (epoch Double).
    /// Search uses LIKE on voteEvent.title (v1).
    static func fetchVotePostItems(_ db: Database, accountId: Int64, search: String?) throws -> [ActivityItem] {
        var sql = """
            SELECT
                voteEvent.entityServerId  AS eventServerPostId,
                voteEvent.voteAction      AS voteAction,
                voteEvent.votedAt         AS votedAt,
                voteEvent.title           AS snapshotTitle,
                voteEvent.communityName   AS snapshotCommunityName,
                voteEvent.communityActorId AS snapshotCommunityActorId,
                voteEvent.thumbnailUrl    AS snapshotThumbnailUrl,
                voteEvent.score           AS snapshotScore,
                post.id                   AS livePostRowId,
                post.postId               AS liveServerPostId,
                post.title                AS liveTitle,
                post.body                 AS liveBody,
                post.originalPostUrl      AS liveOriginalPostUrl,
                post.url                  AS liveUrl,
                post.thumbnailUrl         AS liveThumbnailUrl,
                post.urlEmbedTitle        AS liveUrlEmbedTitle,
                post.urlEmbedDescription  AS liveUrlEmbedDescription,
                post.altText              AS liveAltText,
                post.score                AS liveScore,
                post.numberOfComments     AS liveNumberOfComments,
                post.voteStatus           AS liveVoteStatus,
                post.isRead               AS liveIsRead,
                post.isSaved              AS liveIsSaved,
                post.isRemoved            AS liveIsRemoved,
                post.isLocked             AS liveIsLocked,
                post.isFeaturedCommunity  AS liveIsFeaturedCommunity,
                post.isFeaturedLocal      AS liveIsFeaturedLocal,
                post.isDeleted            AS liveIsDeleted,
                (post.isNsfw OR community.isNsfw) AS liveIsNsfw,
                post.published            AS livePublished,
                community.communityId     AS liveCommunityId,
                community.name            AS liveCommunityName,
                community.actorId         AS liveCommunityActorId,
                creator.personId          AS liveCreatorPersonId,
                creator.name              AS liveCreatorName,
                creator.actorId           AS liveCreatorActorId
            FROM voteEvent
            LEFT JOIN post ON post.accountId = voteEvent.accountId AND post.postId = voteEvent.entityServerId
            LEFT JOIN community ON community.id = post.communityId
            LEFT JOIN person AS creator ON creator.id = post.creatorId
            """
        var args: [any DatabaseValueConvertible] = []
        if let search {
            sql += "\nWHERE voteEvent.accountId = ? AND voteEvent.entityType = 'post' AND voteEvent.title LIKE ?"
            args.append(accountId)
            args.append("%\(search)%")
        } else {
            sql += "\nWHERE voteEvent.accountId = ? AND voteEvent.entityType = 'post'"
            args.append(accountId)
        }
        sql += "\nORDER BY voteEvent.votedAt DESC"

        return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args)).map { row in
            let serverPostId: Int64 = row["eventServerPostId"]
            let voteAction: Int64 = row["voteAction"]
            let votedAtEpoch: Double = row["votedAt"]
            let occurredAt = Date(timeIntervalSince1970: votedAtEpoch)
            let act: ActivityAct = voteAction == 1 ? .upvote : .downvote

            let livePostRowId: Int64? = row["livePostRowId"]
            let postRow: PostListRow
            if let liveId = livePostRowId {
                postRow = PostListRow(
                    id: liveId,
                    serverPostId: row["liveServerPostId"],
                    title: row["liveTitle"] ?? "",
                    body: row["liveBody"],
                    originalPostUrl: row["liveOriginalPostUrl"] ?? "",
                    url: row["liveUrl"],
                    thumbnailUrl: row["liveThumbnailUrl"],
                    urlEmbedTitle: row["liveUrlEmbedTitle"],
                    urlEmbedDescription: row["liveUrlEmbedDescription"],
                    altText: row["liveAltText"],
                    communityName: row["liveCommunityName"] ?? "",
                    communityActorId: row["liveCommunityActorId"],
                    serverCommunityId: row["liveCommunityId"] ?? 0,
                    creatorPersonId: row["liveCreatorPersonId"] ?? 0,
                    creatorName: row["liveCreatorName"],
                    creatorActorId: row["liveCreatorActorId"],
                    score: row["liveScore"] ?? 0,
                    numberOfComments: row["liveNumberOfComments"] ?? 0,
                    voteStatus: row["liveVoteStatus"],
                    isRead: row["liveIsRead"] ?? false,
                    isSaved: row["liveIsSaved"] ?? false,
                    isRemoved: row["liveIsRemoved"] ?? false,
                    isLocked: row["liveIsLocked"] ?? false,
                    isFeaturedCommunity: row["liveIsFeaturedCommunity"] ?? false,
                    isFeaturedLocal: row["liveIsFeaturedLocal"] ?? false,
                    isDeleted: row["liveIsDeleted"] ?? false,
                    isNsfw: row["liveIsNsfw"] ?? false,
                    published: row["livePublished"] ?? occurredAt
                )
            } else {
                postRow = PostListRow(
                    id: 0,
                    serverPostId: serverPostId,
                    title: row["snapshotTitle"] ?? "",
                    body: nil,
                    originalPostUrl: "",
                    url: nil,
                    thumbnailUrl: row["snapshotThumbnailUrl"],
                    urlEmbedTitle: nil,
                    urlEmbedDescription: nil,
                    altText: nil,
                    communityName: row["snapshotCommunityName"] ?? "",
                    communityActorId: row["snapshotCommunityActorId"],
                    serverCommunityId: 0,
                    creatorPersonId: 0,
                    creatorName: nil,
                    creatorActorId: nil,
                    score: row["snapshotScore"] ?? 0,
                    numberOfComments: 0,
                    voteStatus: voteAction,
                    isRead: false,
                    isSaved: false,
                    isRemoved: false,
                    isLocked: false,
                    isFeaturedCommunity: false,
                    isFeaturedLocal: false,
                    isDeleted: false,
                    isNsfw: false,
                    published: occurredAt
                )
            }

            return ActivityItem(
                id: "\(act.rawValue)-post-\(serverPostId)",
                act: act,
                occurredAt: occurredAt,
                object: .post(postRow)
            )
        }
    }

    // MARK: Vote (comment)

    /// LEFT JOINs the live `comment` row for enrichment; falls back to voteEvent snapshot fields
    /// when the comment has not been cached. Account isolation enforced via EXISTS subquery on `post`.
    /// Search uses LIKE on voteEvent.body (v1).
    static func fetchVoteCommentItems(_ db: Database, accountId: Int64, search: String?) throws -> [ActivityItem] {
        var sql = """
            SELECT
                voteEvent.entityServerId   AS eventServerCommentId,
                voteEvent.voteAction       AS voteAction,
                voteEvent.votedAt          AS votedAt,
                voteEvent.body             AS snapshotBody,
                voteEvent.title            AS snapshotParentPostTitle,
                voteEvent.communityName    AS snapshotCommunityName,
                voteEvent.communityActorId AS snapshotCommunityActorId,
                voteEvent.score            AS snapshotScore,
                comment.id                 AS liveCommentRowId,
                comment.localCommentId     AS liveServerCommentId,
                comment.body               AS liveBody,
                comment.score              AS liveScore,
                comment.published          AS livePublished,
                post.postId                AS liveServerPostId,
                post.title                 AS liveParentPostTitle,
                community.name             AS liveCommunityName,
                community.actorId          AS liveCommunityActorId
            FROM voteEvent
            LEFT JOIN comment ON comment.localCommentId = voteEvent.entityServerId
                AND EXISTS (
                    SELECT 1 FROM post p WHERE p.id = comment.postId AND p.accountId = voteEvent.accountId
                )
            LEFT JOIN post ON post.id = comment.postId AND post.accountId = voteEvent.accountId
            LEFT JOIN community ON community.id = post.communityId
            """
        var args: [any DatabaseValueConvertible] = []
        if let search {
            sql += "\nWHERE voteEvent.accountId = ? AND voteEvent.entityType = 'comment' AND voteEvent.body LIKE ?"
            args.append(accountId)
            args.append("%\(search)%")
        } else {
            sql += "\nWHERE voteEvent.accountId = ? AND voteEvent.entityType = 'comment'"
            args.append(accountId)
        }
        sql += "\nORDER BY voteEvent.votedAt DESC"

        return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args)).map { row in
            let serverCommentId: Int64 = row["eventServerCommentId"]
            let voteAction: Int64 = row["voteAction"]
            let votedAtEpoch: Double = row["votedAt"]
            let occurredAt = Date(timeIntervalSince1970: votedAtEpoch)
            let act: ActivityAct = voteAction == 1 ? .upvote : .downvote

            let liveCommentRowId: Int64? = row["liveCommentRowId"]
            let commentRow: ActivityCommentRow
            if let liveId = liveCommentRowId {
                commentRow = ActivityCommentRow(
                    id: liveId,
                    serverCommentId: row["liveServerCommentId"],
                    body: row["liveBody"] ?? "",
                    score: row["liveScore"] ?? 0,
                    parentPostTitle: row["liveParentPostTitle"] ?? "",
                    communityName: row["liveCommunityName"] ?? "",
                    communityActorId: row["liveCommunityActorId"],
                    serverPostId: row["liveServerPostId"],
                    published: row["livePublished"] ?? occurredAt
                )
            } else {
                commentRow = ActivityCommentRow(
                    id: 0,
                    serverCommentId: serverCommentId,
                    body: row["snapshotBody"] ?? "",
                    score: row["snapshotScore"] ?? 0,
                    parentPostTitle: row["snapshotParentPostTitle"] ?? "",
                    communityName: row["snapshotCommunityName"] ?? "",
                    communityActorId: row["snapshotCommunityActorId"],
                    serverPostId: nil,
                    published: occurredAt
                )
            }

            return ActivityItem(
                id: "\(act.rawValue)-comment-\(serverCommentId)",
                act: act,
                occurredAt: occurredAt,
                object: .comment(commentRow)
            )
        }
    }
}
