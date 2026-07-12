//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

public extension PostListRow {
    /// Builds a feed-shaped ``PostListRow`` directly from a network ``LemmyKit/PostView``,
    /// without persisting it to GRDB — used by Search, which renders results straight from
    /// the API through the shared feed cell rather than importing them.
    ///
    /// Every field maps 1:1 from the view, exactly as the feed's importer + observation SQL
    /// do, so a searched post renders identically to a feed post:
    /// - `id` is the server post id (there is no local GRDB row id to key on);
    /// - `isNsfw` folds the post's and the community's flags (`post.nsfw || community.nsfw`),
    ///   matching the feed query's `post.isNsfw OR community.isNsfw`;
    /// - the author-status flags come off v4's `PostView` (site-ban via `creatorBanned`,
    ///   `creatorIsModerator` / `creatorIsAdmin` / `creatorBannedFromCommunity`) and the bare
    ///   creator `Person` (`botAccount` / `deleted`) — the same split the importer mirrors
    ///   onto the joined `post` / `person` rows;
    /// - vote / saved / read come from the per-viewer `postActions` (via the view's derived
    ///   `myVote` / `isSaved` / `isRead`).
    init(view: Lemmy.PostView) {
        let post = view.post

        // Spud stores votes as 1 = up, 0 = down, nil = neutral (matching the importer's
        // `apply(view:)` encoding of the neutral `VoteDirection`).
        let voteStatus: Int64?
        switch view.myVote {
        case .up: voteStatus = 1
        case .down: voteStatus = 0
        case .none: voteStatus = nil
        }

        self.init(
            id: post.id,
            serverPostId: post.id,
            title: post.name,
            body: post.body,
            originalPostUrl: post.apId,
            url: post.url,
            thumbnailUrl: post.thumbnailUrl,
            urlEmbedTitle: post.embedTitle,
            urlEmbedDescription: post.embedDescription,
            altText: post.altText,
            communityName: view.community.name,
            communityActorId: view.community.apId,
            serverCommunityId: view.community.id,
            creatorPersonId: view.creator.id,
            creatorName: view.creator.name,
            creatorActorId: view.creator.apId,
            score: post.score,
            numberOfComments: post.comments,
            voteStatus: voteStatus,
            isRead: view.isRead,
            isSaved: view.isSaved,
            isRemoved: post.removed,
            isLocked: post.locked,
            isFeaturedCommunity: post.featuredCommunity,
            isFeaturedLocal: post.featuredLocal,
            isDeleted: post.deleted,
            isNsfw: post.nsfw || view.community.nsfw,
            isCreatorModerator: view.creatorIsModerator,
            isCreatorAdmin: view.creatorIsAdmin,
            isCreatorBannedFromCommunity: view.creatorBannedFromCommunity,
            isCreatorSiteBanned: view.creatorBanned,
            isCreatorBot: view.creator.botAccount,
            isCreatorAccountDeleted: view.creator.deleted,
            published: post.publishedAt
        )
    }
}
