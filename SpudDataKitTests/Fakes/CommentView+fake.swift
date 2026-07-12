//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

extension Lemmy.CommentView {
    /// A fake neutral ``LemmyKit/CommentView``. `childCount` is now a field on the
    /// neutral ``LemmyKit/Comment`` (v3's `CommentAggregates.child_count` was folded
    /// onto it), so this rebuilds `comment` with the requested count. Per-viewer state
    /// (saved/vote/follow) rides on the optional `commentActions`/`communityActions`.
    static func fake(
        comment: Lemmy.Comment,
        creator: Lemmy.Person,
        post: Lemmy.Post,
        community: Lemmy.Community,
        childCount: Int32,
        creatorBanned: Bool = false,
        commentActions: CommentActions? = nil,
        communityActions: CommunityActions? = nil
    ) -> Lemmy.CommentView {
        let commentWithCount = Lemmy.Comment(
            id: comment.id,
            postId: comment.postId,
            creatorId: comment.creatorId,
            content: comment.content,
            path: comment.path,
            removed: comment.removed,
            deleted: comment.deleted,
            distinguished: comment.distinguished,
            languageId: comment.languageId,
            publishedAt: comment.publishedAt,
            updatedAt: comment.updatedAt,
            apId: comment.apId,
            local: comment.local,
            score: comment.score,
            upvotes: comment.upvotes,
            downvotes: comment.downvotes,
            childCount: Int64(childCount)
        )
        return .init(
            comment: commentWithCount,
            creator: creator,
            post: post,
            community: community,
            creatorBanned: creatorBanned,
            commentActions: commentActions,
            communityActions: communityActions
        )
    }
}
