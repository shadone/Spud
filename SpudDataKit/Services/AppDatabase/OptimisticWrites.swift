//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

/// Targeted single-field writes used by the outbox to apply (and roll back)
/// optimistic state without re-importing a whole entity. Each runs inside a
/// caller-provided transaction so enqueue can keep the projection and the
/// pending-row upsert atomic.
public enum OptimisticWrites {
    // MARK: Post

    public static func setPostVote(
        _ db: Database,
        accountId: Int64,
        serverPostId: Int64,
        voteStatus: Int64?,
        scoreDelta: Int64
    ) throws {
        try db.execute(
            sql: """
                UPDATE post SET voteStatus = ?, score = score + ?
                WHERE postId = ? AND accountId = ?
                """,
            arguments: [voteStatus, scoreDelta, serverPostId, accountId]
        )
    }

    public static func setPostSaved(
        _ db: Database,
        accountId: Int64,
        serverPostId: Int64,
        isSaved: Bool
    ) throws {
        try db.execute(
            sql: "UPDATE post SET isSaved = ? WHERE postId = ? AND accountId = ?",
            arguments: [isSaved, serverPostId, accountId]
        )
    }

    public static func setPostHidden(
        _ db: Database,
        accountId: Int64,
        serverPostId: Int64,
        isHidden: Bool
    ) throws {
        try db.execute(
            sql: "UPDATE post SET isHidden = ? WHERE postId = ? AND accountId = ?",
            arguments: [isHidden, serverPostId, accountId]
        )
    }

    public static func setPostDeleted(
        _ db: Database,
        accountId: Int64,
        serverPostId: Int64,
        isDeleted: Bool
    ) throws {
        try db.execute(
            sql: "UPDATE post SET isDeleted = ? WHERE postId = ? AND accountId = ?",
            arguments: [isDeleted, serverPostId, accountId]
        )
    }

    public static func setPostUnavailable(
        _ db: Database,
        accountId: Int64,
        serverPostId: Int64,
        isUnavailable: Bool
    ) throws {
        try db.execute(
            sql: "UPDATE post SET isUnavailable = ? WHERE postId = ? AND accountId = ?",
            arguments: [isUnavailable, serverPostId, accountId]
        )
    }

    /// Apply an edit's title/body/url/nsfw to the local post row optimistically so
    /// the open post header reflects it immediately, before the content outbox
    /// confirms it server-side. The post-edit reconcile guard keeps these values
    /// from being clobbered by a concurrent feed/`getPost` refresh while the edit
    /// is still pending (sending or failed).
    public static func setPostContent(
        _ db: Database,
        accountId: Int64,
        serverPostId: Int64,
        title: String,
        body: String?,
        url: String?,
        nsfw: Bool
    ) throws {
        try db.execute(
            sql: """
                UPDATE post SET title = ?, body = ?, url = ?, isNsfw = ?
                WHERE postId = ? AND accountId = ?
                """,
            arguments: [title, body, url, nsfw, serverPostId, accountId]
        )
    }

    // MARK: Comment

    /// Comment rows carry no `accountId` column — they join to `post` via
    /// `comment.postId = post.id`. Scope the update through a subquery so the
    /// write touches only comments belonging to the given account.
    public static func setCommentVote(
        _ db: Database,
        accountId: Int64,
        serverCommentId: Int64,
        voteStatus: Int64?,
        scoreDelta: Int64
    ) throws {
        try db.execute(
            sql: """
                UPDATE comment SET voteStatus = ?, score = score + ?
                WHERE localCommentId = ?
                  AND postId IN (SELECT id FROM post WHERE accountId = ?)
                """,
            arguments: [voteStatus, scoreDelta, serverCommentId, accountId]
        )
    }

    public static func setCommentSaved(
        _ db: Database,
        accountId: Int64,
        serverCommentId: Int64,
        isSaved: Bool
    ) throws {
        try db.execute(
            sql: """
                UPDATE comment SET isSaved = ?
                WHERE localCommentId = ?
                  AND postId IN (SELECT id FROM post WHERE accountId = ?)
                """,
            arguments: [isSaved, serverCommentId, accountId]
        )
    }

    public static func setCommentDeleted(
        _ db: Database,
        accountId: Int64,
        serverCommentId: Int64,
        isDeleted: Bool
    ) throws {
        try db.execute(
            sql: """
                UPDATE comment SET isDeleted = ?
                WHERE localCommentId = ?
                  AND postId IN (SELECT id FROM post WHERE accountId = ?)
                """,
            arguments: [isDeleted, serverCommentId, accountId]
        )
    }
}
