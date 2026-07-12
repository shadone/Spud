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
    /// Upserts a single comment row tied to its post. Used by vote/edit flows
    /// where we receive a fresh CommentView for one comment without rebuilding
    /// the whole tree. Skips silently if the post is not yet in AppDatabase.
    ///
    /// When `respectsPendingOutbox` is `true` (the default), any pending
    /// outbox operations for this comment will prevent the corresponding
    /// optimistic fields from being overwritten by server data.
    func upsertComment(
        from view: Lemmy.CommentView,
        accountId: Int64,
        siteId: Int64,
        respectsPendingOutbox: Bool = true
    ) async throws {
        try await writer.write { db in
            guard
                let postRowId = try PostRecord
                .filter(Column("accountId") == accountId)
                .filter(Column("postId") == Int64(view.post.id))
                .fetchOne(db)?
                .id
            else { return }

            _ = try Self.upsertComment(
                from: view,
                accountId: accountId,
                postRowId: postRowId,
                siteId: siteId,
                respectsPendingOutbox: respectsPendingOutbox,
                in: db
            )
        }
    }

    /// Replaces the comment tree for a (post, sortType) pair with the given
    /// CommentViews. Existing CommentElementRecord rows for this post + sort
    /// are deleted, then new ones are inserted in tree-sorted order. Comments
    /// with missing children get an extra "load more" placeholder element.
    ///
    /// Skips the operation if the post is not yet in AppDatabase — the next
    /// `fetchFeed` or `fetchPostInfo` will land it first.
    func upsertComments(
        forServerPostId serverPostId: Int64,
        accountId: Int64,
        siteId: Int64,
        sortType: Lemmy.CommentSortType,
        comments: [Lemmy.CommentView]
    ) async throws {
        guard !comments.isEmpty else { return }

        try await writer.write { db in
            guard
                let postRowId = try PostRecord
                .filter(Column("accountId") == accountId)
                .filter(Column("postId") == serverPostId)
                .fetchOne(db)?
                .id
            else {
                logger.debug("Skipping comment mirror - post \(serverPostId, privacy: .public) not yet in AppDatabase")
                return
            }

            let sortTypeRaw = sortType.rawValue

            // Delete existing element rows for this (post, sortType) pair.
            try CommentElementRecord
                .filter(Column("postId") == postRowId)
                .filter(Column("sortType") == sortTypeRaw)
                .deleteAll(db)

            let commentsWithMissingChildren: Set<Lemmy.CommentID> = Set(
                LemmyCommentImportHelper
                    .findCommentsWithMissingChildren(comments)
                    .map { Lemmy.CommentID($0.comment.id) }
            )

            let ordered = LemmyCommentImportHelper.sort(comments: comments)

            var elementPosition: Int64 = 0
            for view in ordered {
                let path = CommentPath(path: view.comment.path)
                let depth = Int64(path.depth)

                let commentRowId = try Self.upsertComment(
                    from: view,
                    accountId: accountId,
                    postRowId: postRowId,
                    siteId: siteId,
                    respectsPendingOutbox: true,
                    in: db
                )

                var element = CommentElementRecord(
                    postId: postRowId,
                    commentId: commentRowId,
                    position: elementPosition,
                    depth: depth,
                    sortType: sortTypeRaw
                )
                try element.insert(db)
                elementPosition += 1

                if commentsWithMissingChildren.contains(Lemmy.CommentID(view.comment.id)) {
                    var placeholder = CommentElementRecord(
                        postId: postRowId,
                        commentId: nil,
                        position: elementPosition,
                        depth: depth + 1,
                        sortType: sortTypeRaw,
                        moreChildCount: view.comment.childCount,
                        moreParentId: Int64(view.comment.id)
                    )
                    try placeholder.insert(db)
                    elementPosition += 1
                }
            }
        }
    }

    /// Sets the moderator removal reason (mirrored from the public modlog) on
    /// the comments identified by their server comment id, under
    /// `(accountId, serverPostId)`. Skips silently if the post is not mirrored.
    func mirrorCommentRemovalReasons(
        forServerPostId serverPostId: Int64,
        accountId: Int64,
        reasonsByServerCommentId: [Int64: String]
    ) async throws {
        guard !reasonsByServerCommentId.isEmpty else { return }

        try await writer.write { db in
            guard
                let postRowId = try PostRecord
                .filter(Column("accountId") == accountId)
                .filter(Column("postId") == serverPostId)
                .fetchOne(db)?
                .id
            else { return }

            for (serverCommentId, reason) in reasonsByServerCommentId {
                try db.execute(
                    sql: "UPDATE comment SET removedReason = ? WHERE postId = ? AND localCommentId = ?",
                    arguments: [reason, postRowId, serverCommentId]
                )
            }
        }
    }

    private static func upsertComment(
        from view: Lemmy.CommentView,
        accountId: Int64,
        postRowId: Int64,
        siteId: Int64,
        respectsPendingOutbox: Bool,
        in db: Database
    ) throws -> Int64 {
        let creatorId = try AppDatabase.upsertPerson(
            from: view.creator,
            siteId: siteId,
            in: db
        )
        // The neutral bare `Person` carries no site-ban (v4 moved `banned` onto the
        // views), but v4's `CommentView` exposes the creator's instance-wide ban as
        // `creatorBanned`. Mirror it onto the creator's person row so the comment
        // author-status SUSPENDED indicator lights up from a comment-tree import —
        // matching v3, where the bare `Person.banned` set this — instead of only after a
        // separate `PersonView` (profile) import. `PostDetailCommentRow` reads
        // `isCreatorSiteBanned` from the joined `person.isBanned` (mirrors PostImporter).
        // Coupling caveat: `isBanned` is now derived from the view's `creatorBanned` (the
        // neutral bare `Person` no longer carries the site-ban), so a locally-synthesized
        // `CommentView` that defaults `creatorBanned` to `false` would clear a real ban.
        if var creatorRecord = try PersonRecord.fetchOne(db, key: creatorId) {
            creatorRecord.isBanned = view.creatorBanned
            try creatorRecord.update(db)
        }

        let now = Date()
        let serverCommentId = Int64(view.comment.id)

        if var existing = try CommentRecord
            .filter(Column("postId") == postRowId)
            .filter(Column("localCommentId") == serverCommentId)
            .fetchOne(db)
        {
            let pendingKinds = respectsPendingOutbox
                ? try AppDatabase.pendingOutboxKinds(db, accountId: accountId, entityType: "comment", entityServerId: serverCommentId)
                : []
            let preserved = existing
            existing.creatorId = creatorId
            apply(view: view, to: &existing, now: now)
            if pendingKinds.contains(.vote) {
                existing.voteStatus = preserved.voteStatus
                existing.score = preserved.score
                existing.numberOfUpvotes = preserved.numberOfUpvotes
                existing.numberOfDownvotes = preserved.numberOfDownvotes
            }
            if pendingKinds.contains(.save) { existing.isSaved = preserved.isSaved }
            if pendingKinds.contains(.delete) { existing.isDeleted = preserved.isDeleted }
            try existing.update(db)
            return existing.id!
        }

        var record = CommentRecord(
            postId: postRowId,
            creatorId: creatorId,
            localCommentId: serverCommentId,
            body: view.comment.content,
            published: view.comment.publishedAt,
            createdAt: now,
            updatedAt: now
        )
        apply(view: view, to: &record, now: now)
        try record.insert(db)
        return record.id!
    }

    private static func apply(
        view: Lemmy.CommentView,
        to record: inout CommentRecord,
        now: Date
    ) {
        record.body = view.comment.content
        record.originalCommentUrl = view.comment.apId
        record.published = view.comment.publishedAt

        record.score = view.comment.score
        record.numberOfUpvotes = view.comment.upvotes
        record.numberOfDownvotes = view.comment.downvotes
        record.isSaved = view.isSaved

        record.isRemoved = view.comment.removed
        record.isDistinguished = view.comment.distinguished
        record.isDeleted = view.comment.deleted

        record.isCreatorModerator = view.creatorIsModerator
        record.isCreatorAdmin = view.creatorIsAdmin
        record.isCreatorBannedFromCommunity = view.creatorBannedFromCommunity
        record.isCreatorBlocked = view.isCreatorBlocked

        // Map the neutral `VoteDirection` onto the record's stored encoding
        // (1 = upvote, 0 = downvote, nil = no vote).
        switch view.myVote {
        case .up: record.voteStatus = 1
        case .down: record.voteStatus = 0
        case .none: record.voteStatus = nil
        }

        record.updatedAt = now
    }
}
