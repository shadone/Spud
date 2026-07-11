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
    /// Stamps `post.downloadedAt = now` on the post identified by
    /// `serverPostId` for `accountId`, marking it as saved for offline reading.
    ///
    /// This DURABLE marker is what the "Downloaded" feed reads from. The offline
    /// downloader saves feed pages under an ephemeral UUID `feedKey` that the
    /// launch-time ``pruneStaleFeedRows(olderThan:)`` GCs after a few minutes,
    /// but the shared `post` row survives — so the Downloaded feed cannot reopen
    /// the pruned feed and instead relies on this per-post flag.
    ///
    /// Scoped to `accountId` (not `serverPostId` alone) because the `post` table
    /// is keyed by `(accountId, postId)` — several accounts can each hold a
    /// cached copy of the same server post, and a download performed while
    /// browsing one account must not surface in another account's Downloaded
    /// feed. Silently no-ops when the row hasn't been imported yet (the page
    /// fetch that precedes the content phase normally creates it first).
    ///
    /// Binds a `Date` in the record write (the `.datetime` column stores as
    /// ISO-8601 text) rather than a `timeIntervalSince1970` double — see the
    /// CLAUDE.md Date-storage gotcha.
    func markPostDownloaded(serverPostId: Int64, accountId: Int64) async throws {
        try await writer.write { db in
            guard
                var record = try PostRecord
                .filter(Column("accountId") == accountId)
                .filter(Column("postId") == serverPostId)
                .fetchOne(db)
            else { return }
            let now = Date()
            record.downloadedAt = now
            record.updatedAt = now
            try record.update(db)
        }
    }

    /// Stream of ``PostListRow``s for the posts saved for offline reading by the
    /// account identified by `keychainId`, newest download first
    /// (`post.downloadedAt DESC`).
    ///
    /// Selects the SAME columns as the feed's ``observePostListRows(feedId:)`` so
    /// the Downloaded feed renders with the canonical `PostListPostCell` and gets
    /// live vote / save / read / badge updates, but joins `account` and reads
    /// straight from the `post` table filtered by `post.downloadedAt IS NOT NULL`
    /// — there is NO feed / page / pageElement row (the ephemeral download feed
    /// is GC'd; see ``markPostDownloaded(serverPostId:accountId:)``). This renders
    /// entirely from GRDB with no network; the images come from the durable disk
    /// cache the download warmed.
    ///
    /// Unlike ``observePostListRows(feedId:)`` this deliberately does NOT drop
    /// posts whose community is muted: the Downloaded feed is your explicit
    /// offline library, so a post you chose to download stays reachable offline
    /// even if you later mute its community.
    func observeDownloadedPostListRows(
        forAccountKeychainId keychainId: String
    ) -> AsyncStream<[PostListRow]> {
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
                        JOIN account     ON account.id = post.accountId
                        JOIN community   ON community.id = post.communityId
                        JOIN person      AS creator ON creator.id = post.creatorId
                        WHERE account.accountKeychainId = ?
                          AND post.downloadedAt IS NOT NULL
                          AND post.isHidden = 0
                        ORDER BY post.downloadedAt DESC
                    """, arguments: [keychainId])

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
                        isUnavailable: row["isUnavailable"],
                        isNsfw: row["isNsfw"],
                        published: row["published"]
                    )
                }
            }
            .removeDuplicates()

        return AsyncStream { continuation in
            let cancellable = observation.start(in: writer, scheduling: .async(onQueue: .global(qos: .userInitiated))) { error in
                logger.error("DownloadedPostList ValueObservation failed: \(String(describing: error), privacy: .public)")
                continuation.finish()
            } onChange: { value in
                continuation.yield(value)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    /// Synchronous count of posts saved for offline reading by the account
    /// identified by `keychainId`. Gates the Downloaded feed-switcher row and the
    /// offline screen's "View downloaded content" button (both shown only when
    /// this is > 0). Synchronous to match the `*Sync` helper convention.
    func downloadedPostCountSync(forAccountKeychainId keychainId: String) -> Int {
        do {
            return try writer.read { db in
                try Int.fetchOne(db, sql: """
                        SELECT COUNT(*)
                        FROM post
                        JOIN account ON account.id = post.accountId
                        WHERE account.accountKeychainId = ?
                          AND post.downloadedAt IS NOT NULL
                          AND post.isHidden = 0
                    """, arguments: [keychainId]) ?? 0
            }
        } catch {
            logger.error("Failed to count downloaded posts: \(String(describing: error), privacy: .public)")
            return 0
        }
    }
}
