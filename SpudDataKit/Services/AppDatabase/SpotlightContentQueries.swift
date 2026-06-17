//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

/// A row to index into Spotlight: a saved or recently-opened post, with the
/// fields needed to build a `CSSearchableItem` and its routing URL.
public struct IndexableContentRow: Sendable, Equatable {
    public let serverPostId: Int64
    public let title: String
    public let originalPostUrl: String?
    public let thumbnailUrl: String?
    public let communityName: String?
}

public extension AppDatabase {
    /// Saved posts plus the most recently opened posts for the account, newest
    /// first, capped at `limit`. One-shot synchronous read, safe off the main
    /// thread. Joins `postInteraction -> post -> community` (saved state and the
    /// canonical `ap_id` live on `post`, not `postInteraction`).
    func indexableContentRowsSync(forKeychainId keychainId: String, limit: Int) -> [IndexableContentRow] {
        (try? writer.read { db -> [IndexableContentRow] in
            guard let accountId = try Self.accountRowId(forKeychainId: keychainId, in: db) else {
                return []
            }
            let rows = try Row.fetchAll(db, sql: """
                    SELECT
                        post.postId          AS serverPostId,
                        post.title           AS title,
                        post.originalPostUrl AS originalPostUrl,
                        post.thumbnailUrl    AS thumbnailUrl,
                        community.name       AS communityName
                    FROM postInteraction
                    JOIN post      ON post.accountId = postInteraction.accountId AND post.postId = postInteraction.postServerId
                    JOIN community ON community.id = post.communityId
                    WHERE postInteraction.accountId = ?
                      AND (post.isSaved = 1 OR postInteraction.lastOpenedAt IS NOT NULL)
                    ORDER BY post.isSaved DESC, postInteraction.lastOpenedAt DESC
                    LIMIT ?
                """, arguments: [accountId, limit])
            return rows.map { row in
                IndexableContentRow(
                    serverPostId: row["serverPostId"],
                    title: row["title"] ?? "",
                    originalPostUrl: row["originalPostUrl"],
                    thumbnailUrl: row["thumbnailUrl"],
                    communityName: row["communityName"]
                )
            }
        }) ?? []
    }

    /// `indexableContentRowsSync` for the default (non-service) account. Mirrors
    /// `followedCommunitiesForDefaultAccountSync`'s default-account resolution.
    func indexableContentRowsForDefaultAccountSync(limit: Int) -> [IndexableContentRow] {
        let keychainId = (try? writer.read { db -> String? in
            try AccountRecord
                .filter(Column("isServiceAccount") == false)
                .order(sql: "isDefault DESC, id ASC")
                .fetchOne(db)?
                .accountKeychainId
        }) ?? nil
        guard let keychainId else { return [] }
        return indexableContentRowsSync(forKeychainId: keychainId, limit: limit)
    }
}
