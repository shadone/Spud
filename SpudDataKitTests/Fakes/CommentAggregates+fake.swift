//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

extension CommentAggregates {
    static func fake(
        commentId: CommentId,
        childCount: Int32
    ) -> CommentAggregates {
        .init(
            comment_id: commentId,
            score: 1,
            upvotes: 1,
            downvotes: 0,
            published: Date(timeIntervalSince1970: 1_685_938_028),
            child_count: childCount
        )
    }
}
