//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

/// Builders for the **generated v3** (`Components.Schemas.*`) response-payload
/// shapes, used by the stub-transport `LemmyService` tests.
///
/// After the neutral retarget, `Lemmy.Post`/`Comment`/`Community`/`Person`/`Site`
/// and the composed `*View`s resolve to the hand-written neutral structs, which
/// the importers (`upsertPost(from:)` etc.) and neutral endpoint results consume.
/// The stub-transport tests, however, feed a v3 `ClientTransport` that decodes the
/// *generated* response types (`PostResponse.post_view` is a
/// `Components.Schemas.PostView`, not a neutral one), so those payloads must be
/// built from the generated shapes. These helpers rebuild the pre-retarget fakes
/// against `Components.Schemas.*` so a test can encode a valid v3 response for the
/// neutral endpoint to decode and map. Every stored property is a `var` on the
/// generated structs, so callers can still mutate (`view.saved = true`,
/// `post.id = 42`, `view.counts.comments = 3`) after building.
enum V3 {
    static let publishedDate = Date(timeIntervalSince1970: 1_685_577_784)

    static func person(
        id: Lemmy.PersonID = 1,
        name: String = "one"
    ) -> Components.Schemas.Person {
        .init(
            id: id,
            name: name,
            display_name: "One",
            avatar: nil,
            banned: false,
            published: Date(timeIntervalSince1970: 1_683_349_689),
            updated: nil,
            actor_id: "https://example.com/u/\(name)",
            bio: nil,
            local: true,
            banner: nil,
            deleted: false,
            matrix_user_id: nil,
            bot_account: false,
            ban_expires: nil,
            instance_id: 1
        )
    }

    static func community(
        id: Lemmy.CommunityID = 1,
        name: String = "world"
    ) -> Components.Schemas.Community {
        .init(
            id: id,
            name: name,
            title: "World",
            description: "Hello world community",
            removed: false,
            published: Date(timeIntervalSince1970: 1_680_667_628),
            updated: nil,
            deleted: false,
            nsfw: false,
            actor_id: "https://example.com/c/\(name)",
            local: true,
            icon: nil,
            banner: nil,
            hidden: false,
            posting_restricted_to_mods: false,
            instance_id: 1,
            visibility: .Public
        )
    }

    static func post(
        id: Lemmy.PostID = 1,
        creatorId: Lemmy.PersonID = 1,
        communityId: Lemmy.CommunityID = 1,
        nsfw: Bool = false
    ) -> Components.Schemas.Post {
        .init(
            id: id,
            name: "Hello world",
            url: nil,
            body: "Hello example world",
            creator_id: creatorId,
            community_id: communityId,
            removed: false,
            locked: false,
            published: publishedDate,
            updated: nil,
            deleted: false,
            nsfw: nsfw,
            embed_title: nil,
            embed_description: nil,
            thumbnail_url: nil,
            ap_id: "https://example.com/post/\(id)",
            local: true,
            embed_video_url: nil,
            language_id: 1,
            featured_community: false,
            featured_local: false
        )
    }

    static func postAggregates(
        postId: Lemmy.PostID = 1,
        comments: Int64 = 0,
        score: Int64 = 1,
        upvotes: Int64 = 1,
        downvotes: Int64 = 0
    ) -> Components.Schemas.PostAggregates {
        .init(
            post_id: postId,
            comments: comments,
            score: score,
            upvotes: upvotes,
            downvotes: downvotes,
            published: publishedDate,
            newest_comment_time: publishedDate
        )
    }

    static func postView(
        post: Components.Schemas.Post,
        creator: Components.Schemas.Person,
        community: Components.Schemas.Community,
        counts: Components.Schemas.PostAggregates? = nil
    ) -> Components.Schemas.PostView {
        .init(
            post: post,
            creator: creator,
            community: community,
            creator_banned_from_community: false,
            banned_from_community: false,
            creator_is_moderator: false,
            creator_is_admin: false,
            counts: counts ?? postAggregates(postId: post.id),
            subscribed: .NotSubscribed,
            saved: false,
            read: false,
            hidden: false,
            creator_blocked: false,
            my_vote: nil,
            unread_comments: 0
        )
    }

    /// Convenience: build a generated `PostView` for a default post/creator/community.
    static func postView(
        postId: Lemmy.PostID = 1,
        creatorId: Lemmy.PersonID = 1,
        communityId: Lemmy.CommunityID = 1
    ) -> Components.Schemas.PostView {
        postView(
            post: post(id: postId, creatorId: creatorId, communityId: communityId),
            creator: person(id: creatorId),
            community: community(id: communityId)
        )
    }

    static func comment(
        id: Lemmy.CommentID,
        postId: Lemmy.PostID = 1,
        creatorId: Lemmy.PersonID = 1,
        path: String? = nil
    ) -> Components.Schemas.Comment {
        .init(
            id: id,
            creator_id: creatorId,
            post_id: postId,
            content: "hello",
            removed: false,
            published: Date(),
            updated: nil,
            deleted: false,
            ap_id: "https://example.com/comment/\(id)",
            local: true,
            path: path ?? "0.\(id)",
            distinguished: false,
            language_id: 1
        )
    }

    static func commentAggregates(
        commentId: Lemmy.CommentID,
        childCount: Int32 = 0
    ) -> Components.Schemas.CommentAggregates {
        .init(
            comment_id: commentId,
            score: 1,
            upvotes: 1,
            downvotes: 0,
            published: Date(timeIntervalSince1970: 1_685_938_028),
            child_count: childCount
        )
    }

    static func commentView(
        comment: Components.Schemas.Comment,
        creator: Components.Schemas.Person,
        post: Components.Schemas.Post,
        community: Components.Schemas.Community,
        childCount: Int32 = 0
    ) -> Components.Schemas.CommentView {
        .init(
            comment: comment,
            creator: creator,
            post: post,
            community: community,
            counts: commentAggregates(commentId: comment.id, childCount: childCount),
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

    static func communityAggregates(
        communityId: Lemmy.CommunityID = 1,
        subscribers: Int64 = 100,
        posts: Int64 = 50,
        comments: Int64 = 200
    ) -> Components.Schemas.CommunityAggregates {
        .init(
            community_id: communityId,
            subscribers: subscribers,
            posts: posts,
            comments: comments,
            published: Date(timeIntervalSince1970: 1_680_667_628),
            users_active_day: 1,
            users_active_week: 5,
            users_active_month: 10,
            users_active_half_year: 20,
            subscribers_local: subscribers
        )
    }

    static func communityView(
        community: Components.Schemas.Community? = nil,
        subscribed: Lemmy.SubscribedType = .NotSubscribed,
        counts: Components.Schemas.CommunityAggregates? = nil
    ) -> Components.Schemas.CommunityView {
        let community = community ?? self.community()
        return .init(
            community: community,
            subscribed: subscribed,
            blocked: false,
            counts: counts ?? communityAggregates(communityId: community.id),
            banned_from_community: false
        )
    }

    static func personAggregates(
        personId: Lemmy.PersonID = 1,
        postCount: Int64 = 0,
        commentCount: Int64 = 0
    ) -> Components.Schemas.PersonAggregates {
        .init(person_id: personId, post_count: postCount, comment_count: commentCount)
    }

    static func personView(
        person: Components.Schemas.Person? = nil,
        isAdmin: Bool = false,
        postCount: Int64 = 0,
        commentCount: Int64 = 0
    ) -> Components.Schemas.PersonView {
        let person = person ?? self.person()
        return .init(
            person: person,
            counts: personAggregates(personId: person.id, postCount: postCount, commentCount: commentCount),
            is_admin: isAdmin
        )
    }

    static func privateMessage(
        id: Lemmy.PrivateMessageID,
        creatorId: Lemmy.PersonID,
        recipientId: Lemmy.PersonID,
        content: String = "hi there",
        read: Bool = false
    ) -> Components.Schemas.PrivateMessage {
        .init(
            id: id,
            creator_id: creatorId,
            recipient_id: recipientId,
            content: content,
            deleted: false,
            read: read,
            published: Date(timeIntervalSince1970: 1_700_000_000),
            ap_id: "https://example.com/pm/\(id)",
            local: true
        )
    }

    static func privateMessageView(
        id: Lemmy.PrivateMessageID,
        creator: Components.Schemas.Person,
        recipient: Components.Schemas.Person,
        content: String = "hi there",
        read: Bool = false
    ) -> Components.Schemas.PrivateMessageView {
        .init(
            private_message: privateMessage(
                id: id,
                creatorId: creator.id,
                recipientId: recipient.id,
                content: content,
                read: read
            ),
            creator: creator,
            recipient: recipient
        )
    }
}
