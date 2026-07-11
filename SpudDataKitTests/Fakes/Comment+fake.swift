//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

extension Lemmy.Comment {
    /// A fake neutral ``LemmyKit/Comment``. v4-shaped: the vote aggregates
    /// (`score`/`upvotes`/`downvotes`) and `childCount` are flattened onto the
    /// comment itself rather than living on a separate `CommentAggregates` object.
    static func fake(
        id: Lemmy.CommentID,
        post: Lemmy.Post,
        creator: Lemmy.Person,
        parent: CommentPath,
        childCount: Int64 = 0
    ) -> Lemmy.Comment {
        .init(
            id: Int64(id),
            postId: post.id,
            creatorId: creator.id,
            content: "hello",
            path: parent.appending(id).pathString,
            removed: false,
            deleted: false,
            distinguished: false,
            languageId: 1,
            publishedAt: Date(),
            updatedAt: nil,
            apId: "https://example.com/comment/1",
            local: true,
            score: 1,
            upvotes: 1,
            downvotes: 0,
            childCount: childCount
        )
    }
}
