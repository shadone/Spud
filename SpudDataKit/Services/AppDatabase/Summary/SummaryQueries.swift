//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

public extension AppDatabase {
    /// Count of posts and comments the account has saved (`isSaved = 1`).
    ///
    /// Comment saves are isolated by joining through their parent post's
    /// `accountId`, matching the pattern used by `fetchSavedCommentItems`.
    func countSavedItems(accountId: Int64) throws -> Int {
        try writer.read { db in
            let posts = try Int.fetchOne(
                db,
                sql: "SELECT count(*) FROM post WHERE accountId = ? AND isSaved = 1",
                arguments: [accountId]
            ) ?? 0
            let comments = try Int.fetchOne(
                db,
                sql: """
                    SELECT count(*)
                    FROM comment
                    JOIN post ON post.id = comment.postId
                    WHERE post.accountId = ? AND comment.isSaved = 1
                    """,
                arguments: [accountId]
            ) ?? 0
            return posts + comments
        }
    }

    /// Count of posts the account has opened at least once
    /// (`postInteraction.lastOpenedAt IS NOT NULL`).
    func countReadItems(accountId: Int64) throws -> Int {
        try writer.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT count(*)
                    FROM postInteraction
                    WHERE accountId = ? AND lastOpenedAt IS NOT NULL
                    """,
                arguments: [accountId]
            ) ?? 0
        }
    }

    /// Count of vote-log entries for the account (`voteEvent` rows).
    ///
    /// This is a forward-only tally: rows accumulate as the user votes; there
    /// is no backfill from the server.
    func countVoteEvents(accountId: Int64) throws -> Int {
        try writer.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT count(*) FROM voteEvent WHERE accountId = ?",
                arguments: [accountId]
            ) ?? 0
        }
    }

    /// Count of communities the account follows
    /// (`accountFollowedCommunity` rows).
    func countFollowedCommunities(accountId: Int64) throws -> Int {
        try writer.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT count(*) FROM accountFollowedCommunity WHERE accountId = ?",
                arguments: [accountId]
            ) ?? 0
        }
    }
}
