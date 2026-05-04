//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

extension Components.Schemas.CommentView {
    static func fake(
        comment: Components.Schemas.Comment,
        creator: Components.Schemas.Person,
        post: Components.Schemas.Post,
        community: Components.Schemas.Community,
        childCount: Int32
    ) -> Components.Schemas.CommentView {
        .init(
            comment: comment,
            creator: creator,
            post: post,
            community: community,
            counts: .fake(commentId: comment.id, childCount: childCount),
            creator_banned_from_community: false,
            banned_from_community: false,
            creator_is_moderator: false,
            creator_is_admin: false,
            subscribed: .NotSubscribed,
            saved: false,
            creator_blocked: false,
            my_vote: nil
        )
    }
}
