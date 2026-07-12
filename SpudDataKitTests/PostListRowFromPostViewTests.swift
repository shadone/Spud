//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import Testing
@testable import SpudDataKit

/// Verifies `PostListRow(view:)` maps every field off a network `PostView` exactly as
/// the feed's importer + observation do, so a searched post renders identically to a
/// feed post (community@instance, counts, thumbnail, NSFW fold, author-status, and
/// vote/save/read from `postActions`).
struct PostListRowFromPostViewTests {
    private func makePost(nsfw: Bool) -> Lemmy.Post {
        Lemmy.Post(
            id: 42,
            name: "Mapped title",
            body: "Mapped body",
            url: "https://example.com/article",
            embedTitle: "Embed title",
            embedDescription: "Embed description",
            thumbnailUrl: "https://example.com/thumb.jpg",
            altText: "Alt text",
            imageWidth: 800,
            imageHeight: 600,
            creatorId: 5,
            communityId: 8,
            apId: "https://example.com/post/42",
            local: true,
            nsfw: nsfw,
            removed: true,
            deleted: true,
            locked: true,
            featuredCommunity: true,
            featuredLocal: true,
            languageId: 1,
            publishedAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: nil,
            newestCommentTimeAt: nil,
            score: 99,
            upvotes: 120,
            downvotes: 21,
            comments: 7
        )
    }

    private func makeCommunity(nsfw: Bool) -> Lemmy.Community {
        Lemmy.Community(
            id: 8,
            name: "tech",
            title: "Technology",
            sidebar: nil,
            apId: "https://example.com/c/tech",
            iconUrl: nil,
            bannerUrl: nil,
            visibility: ._public,
            local: true,
            nsfw: nsfw,
            postingRestrictedToMods: false,
            removed: false,
            deleted: false,
            publishedAt: Date(timeIntervalSince1970: 1_680_000_000),
            updatedAt: nil,
            subscribers: 100,
            posts: 50,
            comments: 200
        )
    }

    @Test
    func mapsEveryField() {
        let creator = Lemmy.Person.fake(
            id: 5,
            name: "bob",
            displayName: "Bob",
            botAccount: true,
            deleted: true
        )
        let post = makePost(nsfw: false)
        let community = makeCommunity(nsfw: true)
        let view = Lemmy.PostView.fake(
            post: post,
            creator: creator,
            community: community,
            creatorBannedFromCommunity: true,
            creatorIsModerator: true,
            creatorIsAdmin: true,
            creatorBanned: true,
            postActions: PostActions(
                readAt: Date(timeIntervalSince1970: 1_700_000_100),
                savedAt: Date(timeIntervalSince1970: 1_700_000_200),
                votedAt: Date(timeIntervalSince1970: 1_700_000_300),
                voteIsUpvote: true
            )
        )

        let row = PostListRow(view: view)

        // Identity / post core.
        #expect(row.id == 42)
        #expect(row.serverPostId == 42)
        #expect(row.title == "Mapped title")
        #expect(row.body == "Mapped body")
        #expect(row.originalPostUrl == "https://example.com/post/42")
        #expect(row.url == "https://example.com/article")
        #expect(row.thumbnailUrl == "https://example.com/thumb.jpg")
        #expect(row.urlEmbedTitle == "Embed title")
        #expect(row.urlEmbedDescription == "Embed description")
        #expect(row.altText == "Alt text")
        #expect(row.published == Date(timeIntervalSince1970: 1_700_000_000))

        // Community + creator identity.
        #expect(row.communityName == "tech")
        #expect(row.communityActorId == "https://example.com/c/tech")
        #expect(row.serverCommunityId == 8)
        #expect(row.creatorPersonId == 5)
        #expect(row.creatorName == "bob")
        #expect(row.creatorActorId == "https://example.com/u/bob")

        // Counts + per-viewer state.
        #expect(row.score == 99)
        #expect(row.numberOfComments == 7)
        #expect(row.voteStatus == 1) // upvote
        #expect(row.isRead == true)
        #expect(row.isSaved == true)

        // NSFW folds post || community (post is SFW here, community is NSFW).
        #expect(row.isNsfw == true)

        // Moderation / content status.
        #expect(row.isRemoved == true)
        #expect(row.isLocked == true)
        #expect(row.isFeaturedCommunity == true)
        #expect(row.isFeaturedLocal == true)
        #expect(row.isDeleted == true)
        #expect(row.isUnavailable == false)

        // Author status: from the PostView (site-ban/mod/admin/banned-from-community)
        // and the bare Person (bot/deleted).
        #expect(row.isCreatorSiteBanned == true)
        #expect(row.isCreatorModerator == true)
        #expect(row.isCreatorAdmin == true)
        #expect(row.isCreatorBannedFromCommunity == true)
        #expect(row.isCreatorBot == true)
        #expect(row.isCreatorAccountDeleted == true)
    }

    @Test
    func nsfwFold_postNsfwOnly_isNsfw() {
        let view = Lemmy.PostView.fake(
            post: makePost(nsfw: true),
            creator: .fake(id: 5, name: "bob"),
            community: makeCommunity(nsfw: false)
        )
        #expect(PostListRow(view: view).isNsfw == true)
    }

    @Test
    func voteAndSaved_defaultToNeutralWhenNoActions() {
        // A signed-out viewer (no postActions) has no vote, saved, or read state.
        let view = Lemmy.PostView.fake(
            post: makePost(nsfw: false),
            creator: .fake(id: 5, name: "bob"),
            community: makeCommunity(nsfw: false)
        )
        let row = PostListRow(view: view)
        #expect(row.voteStatus == nil)
        #expect(row.isSaved == false)
        #expect(row.isRead == false)
        #expect(row.isNsfw == false)
    }
}
