//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

extension CommentView {
    static func fake(
        comment: Comment,
        creator: Person,
        post: Post,
        community: Community,
        childCount: Int32
    ) -> CommentView {
        .init(
            comment: comment,
            creator: creator,
            post: post,
            community: community,
            counts: .fake(commentId: comment.id, childCount: childCount),
            creator_banned_from_community: false,
            subscribed: .notSubscribed,
            saved: false,
            creator_blocked: false,
            my_vote: nil
        )
    }
}
