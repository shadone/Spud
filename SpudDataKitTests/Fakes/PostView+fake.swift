//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

extension Lemmy.PostView {
    /// A fake neutral ``LemmyKit/PostView``. Per-viewer state (saved/read/hidden/
    /// vote/follow) rides on the optional `postActions`/`communityActions` structs
    /// rather than the old flat `saved`/`read`/`my_vote`/`subscribed` fields — pass
    /// them to model a signed-in viewer's relationship to the post.
    static func fake(
        post: Lemmy.Post,
        creator: Lemmy.Person,
        community: Lemmy.Community,
        creatorBannedFromCommunity: Bool = false,
        creatorIsModerator: Bool = false,
        creatorIsAdmin: Bool = false,
        postActions: PostActions? = nil,
        communityActions: CommunityActions? = nil
    ) -> Lemmy.PostView {
        .init(
            post: post,
            creator: creator,
            community: community,
            creatorBannedFromCommunity: creatorBannedFromCommunity,
            creatorIsModerator: creatorIsModerator,
            creatorIsAdmin: creatorIsAdmin,
            postActions: postActions,
            communityActions: communityActions
        )
    }
}
