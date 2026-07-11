//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

extension Lemmy.Post {
    /// A fake neutral ``LemmyKit/Post``. v4-shaped: the vote/comment aggregates
    /// (`score`/`upvotes`/`downvotes`/`comments`) are flattened onto the post
    /// itself rather than living on a separate `PostAggregates` object.
    static func fake(
        creator: Lemmy.Person,
        community: Lemmy.Community,
        nsfw: Bool = false,
        id: Lemmy.PostID = 1,
        score: Int64 = 1,
        comments: Int64 = 0
    ) -> Lemmy.Post {
        .init(
            id: Int64(id),
            name: "Hello world",
            body: "Hello example world",
            url: nil,
            embedTitle: nil,
            embedDescription: nil,
            thumbnailUrl: nil,
            altText: nil,
            creatorId: creator.id,
            communityId: community.id,
            apId: "https://example.com/post/\(id)",
            local: true,
            nsfw: nsfw,
            removed: false,
            deleted: false,
            locked: false,
            featuredCommunity: false,
            featuredLocal: false,
            languageId: 1,
            publishedAt: Date(timeIntervalSince1970: 1_685_577_784),
            updatedAt: nil,
            newestCommentTimeAt: Date(timeIntervalSince1970: 1_685_577_784),
            score: score,
            upvotes: 1,
            downvotes: 0,
            comments: comments
        )
    }
}
