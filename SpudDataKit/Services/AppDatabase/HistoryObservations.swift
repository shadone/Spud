//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import OSLog

private let logger = Logger.appDatabase

/// Which slice of the local interaction history to show.
public enum HistoryMode: Sendable, CaseIterable {
    /// Posts the user opened, newest-opened first.
    case read
    /// Every post the user encountered (opened or merely seen on screen),
    /// most-recently-encountered first.
    case seen
    /// Encountered posts that are currently saved, most-recently-encountered first.
    case saved
}

public extension AppDatabase {
    /// Stream of History rows for the account, reusing the feed `PostListRow`
    /// type so the History screen can drive the existing post cell. INNER JOINs
    /// `postInteraction -> post -> community -> person` (a post is never evicted
    /// while its account exists, so the join always matches). `searchQuery`, when
    /// non-empty, narrows via the FTS5 index over the interaction snapshot.
    func observeHistoryRows(
        forKeychainId keychainId: String,
        mode: HistoryMode,
        searchQuery: String?
    ) -> AsyncStream<[PostListRow]> {
        // Most-recently-encountered ordering: the larger of the two timestamps,
        // NULLs coalesced to '' (which sorts before any real timestamp text).
        let encounteredExpr = "max(coalesce(postInteraction.lastSeenAt, ''), coalesce(postInteraction.lastOpenedAt, ''))"
        let (modeWhere, orderBy): (String, String)
        switch mode {
        case .read:
            modeWhere = "AND postInteraction.lastOpenedAt IS NOT NULL"
            orderBy = "postInteraction.lastOpenedAt DESC"
        case .seen:
            modeWhere = "" // no extra filter: every interaction with this account qualifies
            orderBy = "\(encounteredExpr) DESC"
        case .saved:
            modeWhere = "AND post.isSaved = 1"
            orderBy = "\(encounteredExpr) DESC"
        }

        let trimmed = searchQuery?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasSearch = !(trimmed?.isEmpty ?? true)

        let observation = ValueObservation
            .tracking { [hasSearch, modeWhere, orderBy, trimmed] db -> [PostListRow] in
                guard let accountId = try Self.accountRowId(forKeychainId: keychainId, in: db) else {
                    return []
                }

                var sql = """
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
                        post.published         AS published,
                        community.communityId  AS serverCommunityId,
                        community.name         AS communityName,
                        community.actorId      AS communityActorId,
                        creator.personId       AS creatorPersonId,
                        creator.name           AS creatorName,
                        creator.actorId        AS creatorActorId
                    FROM postInteraction
                    JOIN post      ON post.accountId = postInteraction.accountId AND post.postId = postInteraction.postServerId
                    JOIN community ON community.id = post.communityId
                    JOIN person    AS creator ON creator.id = post.creatorId
                    """

                var arguments: [any DatabaseValueConvertible] = []
                if hasSearch, let trimmed, let pattern = FTS5Pattern(matchingAllTokensIn: trimmed) {
                    // MATCH spans all accounts; the WHERE postInteraction.accountId clause below is what enforces account isolation.
                    sql += "\nJOIN postInteractionFts ON postInteractionFts.rowid = postInteraction.id AND postInteractionFts MATCH ?"
                    arguments.append(pattern)
                }
                sql += "\nWHERE postInteraction.accountId = ? \(modeWhere)"
                arguments.append(accountId)
                sql += "\nORDER BY \(orderBy)"

                let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
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
                        published: row["published"]
                    )
                }
            }
            .removeDuplicates()

        return AsyncStream { continuation in
            let cancellable = observation.start(in: writer, scheduling: .async(onQueue: .global(qos: .userInitiated))) { error in
                logger.error("History ValueObservation failed: \(String(describing: error), privacy: .public)")
                continuation.finish()
            } onChange: { value in
                continuation.yield(value)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }
}
