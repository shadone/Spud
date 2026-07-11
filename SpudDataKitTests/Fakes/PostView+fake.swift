//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

extension Components.Schemas.PostAggregates {
    static func fake(post: Components.Schemas.Post) -> Components.Schemas.PostAggregates {
        .init(
            post_id: post.id,
            comments: 0,
            score: 1,
            upvotes: 1,
            downvotes: 0,
            published: post.published,
            newest_comment_time: post.published
        )
    }
}

extension Components.Schemas.PostView {
    static func fake(
        post: Components.Schemas.Post,
        creator: Components.Schemas.Person,
        community: Components.Schemas.Community,
        creatorBannedFromCommunity: Bool = false,
        creatorIsModerator: Bool = false,
        creatorIsAdmin: Bool = false
    ) -> Components.Schemas.PostView {
        .init(
            post: post,
            creator: creator,
            community: community,
            creator_banned_from_community: creatorBannedFromCommunity,
            banned_from_community: false,
            creator_is_moderator: creatorIsModerator,
            creator_is_admin: creatorIsAdmin,
            counts: .fake(post: post),
            subscribed: .NotSubscribed,
            saved: false,
            read: false,
            hidden: false,
            creator_blocked: false,
            my_vote: nil,
            unread_comments: 0
        )
    }
}
