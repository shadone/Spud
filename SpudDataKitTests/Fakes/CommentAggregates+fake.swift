//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
@testable import LemmyKit

extension CommentAggregates {
    static func fake(
        commentId: CommentId,
        childCount: Int32
    ) -> CommentAggregates {
        .init(
            id: 1,
            comment_id: commentId,
            score: 1,
            upvotes: 1,
            downvotes: 0,
            published: Date(timeIntervalSince1970: 1685938028),
            child_count: childCount,
            hot_rank: 0
        )
    }
}
