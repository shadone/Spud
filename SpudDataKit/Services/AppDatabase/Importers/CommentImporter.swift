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

extension AppDatabase {
    /// Upserts a single comment row tied to its post. Used by vote/edit flows
    /// where we receive a fresh CommentView for one comment without rebuilding
    /// the whole tree. Skips silently if the post is not yet in AppDatabase.
    public func upsertComment(
        from view: Components.Schemas.CommentView,
        accountId: Int64,
        siteId: Int64
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
                postRowId: postRowId,
                siteId: siteId,
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
    public func upsertComments(
        forServerPostId serverPostId: Int64,
        accountId: Int64,
        siteId: Int64,
        sortType: Components.Schemas.CommentSortType,
        comments: [Components.Schemas.CommentView]
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

            let commentsWithMissingChildren: Set<Components.Schemas.CommentID> = Set(
                LemmyCommentImportHelper
                    .findCommentsWithMissingChildren(comments)
                    .map(\.comment.id)
            )

            let ordered = LemmyCommentImportHelper.sort(comments: comments)

            var elementPosition: Int64 = 0
            for view in ordered {
                let path = CommentPath(path: view.comment.path)
                let depth = Int64(path.depth)

                let commentRowId = try Self.upsertComment(
                    from: view,
                    postRowId: postRowId,
                    siteId: siteId,
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

                if commentsWithMissingChildren.contains(view.comment.id) {
                    var placeholder = CommentElementRecord(
                        postId: postRowId,
                        commentId: nil,
                        position: elementPosition,
                        depth: depth + 1,
                        sortType: sortTypeRaw,
                        moreChildCount: Int64(view.counts.child_count),
                        moreParentId: Int64(view.comment.id)
                    )
                    try placeholder.insert(db)
                    elementPosition += 1
                }
            }
        }
    }

    private static func upsertComment(
        from view: Components.Schemas.CommentView,
        postRowId: Int64,
        siteId: Int64,
        in db: Database
    ) throws -> Int64 {
        let creatorId = try AppDatabase.upsertPerson(
            from: view.creator,
            siteId: siteId,
            in: db
        )

        let now = Date()
        let serverCommentId = Int64(view.comment.id)

        if var existing = try CommentRecord
            .filter(Column("postId") == postRowId)
            .filter(Column("localCommentId") == serverCommentId)
            .fetchOne(db)
        {
            existing.creatorId = creatorId
            apply(view: view, to: &existing, now: now)
            try existing.update(db)
            return existing.id!
        }

        var record = CommentRecord(
            postId: postRowId,
            creatorId: creatorId,
            localCommentId: serverCommentId,
            body: view.comment.content,
            published: view.comment.published,
            createdAt: now,
            updatedAt: now
        )
        apply(view: view, to: &record, now: now)
        try record.insert(db)
        return record.id!
    }

    private static func apply(
        view: Components.Schemas.CommentView,
        to record: inout CommentRecord,
        now: Date
    ) {
        record.body = view.comment.content
        record.originalCommentUrl = view.comment.ap_id
        record.published = view.comment.published

        record.score = Int64(view.counts.score)
        record.numberOfUpvotes = Int64(view.counts.upvotes)
        record.numberOfDownvotes = Int64(view.counts.downvotes)
        record.isSaved = view.saved

        switch view.my_vote {
        case 1: record.voteStatus = 1
        case -1: record.voteStatus = 0
        case 0, nil: record.voteStatus = nil
        default:
            logger.assertionFailure("Unexpected my_vote \(String(describing: view.my_vote)) for comment \(view.comment.id)")
            record.voteStatus = nil
        }

        record.updatedAt = now
    }
}
