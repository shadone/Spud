//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import LemmyKit
import OSLog

private let logger = Logger.appDatabase

public extension AppDatabase {
    /// Stream of `PostListRow`s for the posts a given person authored, scoped to
    /// `accountId`. Selects the SAME columns as the feed's `observePostListRows`
    /// (so the Person profile renders posts with the canonical `PostListPostCell`
    /// and gets live vote / save / read / badge updates), but joins
    /// `post -> community -> person AS creator` directly — there is no feed page
    /// for a profile, so the rows come straight from the `post` table filtered by
    /// `creatorId`.
    ///
    /// The posts are persisted by `LemmyService.fetchPersonContent`, which routes
    /// `getPersonDetails`' `posts` through the batch `upsertPosts` importer; after
    /// that import the post's `creatorId` points at this profile's person row.
    ///
    /// `sort` matches the profile's sort control: New / Old order by
    /// `published`, every `Top*` orders by `score DESC`. Anything else falls back
    /// to New (`published DESC`).
    func observePersonPostListRows(
        personRowId: Int64,
        accountId: Int64,
        sort: Lemmy.SortType
    ) -> AsyncStream<[PostListRow]> {
        let orderClause: String
        switch sort {
        case .Old:
            orderClause = "post.published ASC"
        case .TopSixHour, .TopTwelveHour, .TopDay, .TopWeek, .TopMonth, .TopYear,
             .TopAll, .TopThreeMonths, .TopSixMonths, .TopNineMonths:
            orderClause = "post.score DESC, post.published DESC"
        case .New, .Hot, .Active, .MostComments, .NewComments, .Controversial, .Scaled:
            orderClause = "post.published DESC"
        }

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
                            (post.isNsfw OR community.isNsfw) AS isNsfw,
                            post.published         AS published,
                            community.communityId  AS serverCommunityId,
                            community.name         AS communityName,
                            community.actorId      AS communityActorId,
                            creator.personId       AS creatorPersonId,
                            creator.name           AS creatorName,
                            creator.actorId        AS creatorActorId
                        FROM post
                        JOIN community   ON community.id = post.communityId
                        JOIN person      AS creator ON creator.id = post.creatorId
                        WHERE post.creatorId = ?
                          AND post.accountId = ?
                          AND post.isHidden = 0
                        ORDER BY \(orderClause)
                    """, arguments: [personRowId, accountId])

                return rows.map { row -> PostListRow in
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
            }
            .removeDuplicates()

        return AsyncStream { continuation in
            let cancellable = observation.start(in: writer, scheduling: .async(onQueue: .global(qos: .userInitiated))) { error in
                logger.error("PersonPostList ValueObservation failed: \(String(describing: error), privacy: .public)")
                continuation.finish()
            } onChange: { value in
                continuation.yield(value)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }
}
