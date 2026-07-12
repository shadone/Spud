//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import OSLog

private let logger = Logger.appDatabase

/// One row per cross-post of an opened post — another post sharing its link,
/// harvested from `PostDetail.crossPosts` and persisted to the `postCrossPost`
/// junction by `LemmyService.fetchPostInfo`. Backs the post-detail "Cross-posted
/// to N communities" section.
public struct CrossPostSummary: Sendable, Equatable, Identifiable {
    public var id: Int64 {
        serverPostId
    }

    public let serverPostId: Int64
    /// The cross-post's federation permalink (`post.ap_id`). Used to open it via
    /// the app's internal-link routing (`.objectAtURL`), which resolves the
    /// federated object regardless of which instance the cross-post lives on.
    public let apId: String
    public let communityName: String
    /// The cross-post's community federation actor id (e.g.
    /// "https://lemmy.world/c/world"), used to derive the "c/name@instance"
    /// display handle. nil if the community row has no actorId.
    public let communityActorId: String?
    public let score: Int64
    public let commentCount: Int64

    public init(
        serverPostId: Int64,
        apId: String,
        communityName: String,
        communityActorId: String?,
        score: Int64,
        commentCount: Int64
    ) {
        self.serverPostId = serverPostId
        self.apId = apId
        self.communityName = communityName
        self.communityActorId = communityActorId
        self.score = score
        self.commentCount = commentCount
    }
}

public extension AppDatabase {
    /// The cross-posts of `serverPostId` under `keychainId`'s account, in the
    /// server's original order (`postCrossPost.position`). Joins
    /// `postCrossPost -> post -> community` so the section can render without
    /// further lookups. Empty when the post has no cross-posts (or was never
    /// fetched with `fetchPostInfo`, or isn't mirrored).
    ///
    /// A one-shot read, not a live observation: cross-posts don't change while
    /// viewing a post, so the caller (`PostDetailViewModel`) re-reads this after
    /// each `fetchPostInfo` (initial load + pull-to-refresh) rather than
    /// subscribing to a stream.
    func crossPostSummariesSync(forKeychainId keychainId: String, serverPostId: Int64) -> [CrossPostSummary] {
        do {
            return try writer.read { db -> [CrossPostSummary] in
                guard let accountId = try Self.accountRowId(forKeychainId: keychainId, in: db) else {
                    return []
                }
                guard let postRowId = try PostRecord
                    .filter(Column("accountId") == accountId)
                    .filter(Column("postId") == serverPostId)
                    .fetchOne(db)?
                    .id
                else {
                    return []
                }

                let rows = try Row.fetchAll(db, sql: """
                        SELECT
                            post.postId            AS serverPostId,
                            post.originalPostUrl   AS apId,
                            community.name         AS communityName,
                            community.actorId      AS communityActorId,
                            post.score             AS score,
                            post.numberOfComments  AS commentCount
                        FROM postCrossPost
                        JOIN post      ON post.id = postCrossPost.crossPostId
                        JOIN community ON community.id = post.communityId
                        WHERE postCrossPost.postId = ?
                        ORDER BY postCrossPost.position ASC
                    """, arguments: [postRowId])

                return rows.map { row in
                    CrossPostSummary(
                        serverPostId: row["serverPostId"],
                        apId: row["apId"] ?? "",
                        communityName: row["communityName"] ?? "",
                        communityActorId: row["communityActorId"],
                        score: row["score"],
                        commentCount: row["commentCount"]
                    )
                }
            }
        } catch {
            logger.error("crossPostSummariesSync failed: \(String(describing: error), privacy: .public)")
            return []
        }
    }
}
