//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
@testable import LemmyKit

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
            counts: .init(
                id: 1,
                comment_id: comment.id,
                score: 1,
                upvotes: 1,
                downvotes: 0,
                published: Date(timeIntervalSince1970: 1685938028),
                child_count: childCount
            ),
            creator_banned_from_community: false,
            subscribed: .notSubscribed,
            saved: false,
            creator_blocked: false,
            my_vote: nil
        )
    }
}
