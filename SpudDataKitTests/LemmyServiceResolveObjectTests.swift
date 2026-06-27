//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SpudUtilKit
import Testing
@testable import SpudDataKit

struct LemmyServiceResolveObjectTests {
    private let home = InstanceActorId(from: "https://lemmy.world")!

    @Test
    func mapsPostResponse_toPostCaseWithHomeInstance() {
        var post = Components.Schemas.Post.fake(creator: .fake, community: .fake)
        post.id = 77
        let view = Components.Schemas.PostView.fake(post: post, creator: .fake, community: .fake)
        let resolved = ResolvedLemmyObject(
            response: Components.Schemas.ResolveObjectResponse(post: view),
            homeInstance: home
        )
        guard case let .post(postId, instance) = resolved else {
            Issue.record("expected .post")
            return
        }
        #expect(postId == 77)
        #expect(instance.host == "lemmy.world")
    }

    @Test
    func mapsCommunityResponse_toCommunityCaseFromActorId() {
        var community = Components.Schemas.Community.fake
        community.name = "technology"
        community.actor_id = "https://beehaw.org/c/technology"
        let view = Components.Schemas.CommunityView.fake(community: community)
        let resolved = ResolvedLemmyObject(
            response: Components.Schemas.ResolveObjectResponse(community: view),
            homeInstance: home
        )
        guard case let .community(name, instance) = resolved else {
            Issue.record("expected .community")
            return
        }
        #expect(name == "technology")
        #expect(instance.host == "beehaw.org")
    }

    @Test
    func emptyResponse_isUnresolved() {
        let resolved = ResolvedLemmyObject(
            response: Components.Schemas.ResolveObjectResponse(),
            homeInstance: home
        )
        guard case .unresolved = resolved else {
            Issue.record("expected .unresolved")
            return
        }
    }

    @Test
    func mapsPersonResponse_toPersonCase() {
        var person = Components.Schemas.Person.fake
        person.id = 55
        let view = Components.Schemas.PersonView.fake(person: person)
        let resolved = ResolvedLemmyObject(
            response: Components.Schemas.ResolveObjectResponse(person: view),
            homeInstance: home
        )
        guard case let .person(personId, instance) = resolved else {
            Issue.record("expected .person")
            return
        }
        #expect(personId == 55)
        #expect(instance.host == "lemmy.world")
    }

    @Test
    func mapsCommentResponse_toCommentCaseWithPostAndCommentIds() {
        var post = Components.Schemas.Post.fake(creator: .fake, community: .fake)
        post.id = 42
        let comment = Components.Schemas.Comment.fake(
            id: 7,
            post: post,
            creator: .fake,
            parent: .root
        )
        let view = Components.Schemas.CommentView.fake(
            comment: comment,
            creator: .fake,
            post: post,
            community: .fake,
            childCount: 0
        )
        let resolved = ResolvedLemmyObject(
            response: Components.Schemas.ResolveObjectResponse(comment: view),
            homeInstance: home
        )
        guard case let .comment(postId, commentId, instance) = resolved else {
            Issue.record("expected .comment")
            return
        }
        #expect(postId == 42)
        #expect(commentId == 7)
        #expect(instance.host == "lemmy.world")
    }
}
