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
        let post = Lemmy.Post.fake(creator: .fake, community: .fake, id: 77)
        let view = Lemmy.PostView.fake(post: post, creator: .fake, community: .fake)
        let resolved = ResolvedLemmyObject(
            response: .post(view),
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
        let community = Lemmy.Community.fake(
            name: "technology",
            apId: "https://beehaw.org/c/technology"
        )
        let view = Lemmy.CommunityView.fake(community: community)
        let resolved = ResolvedLemmyObject(
            response: .community(view),
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
            response: nil,
            homeInstance: home
        )
        guard case .unresolved = resolved else {
            Issue.record("expected .unresolved")
            return
        }
    }

    @Test
    func mapsPersonResponse_toPersonCase() {
        let person = Lemmy.Person.fake(id: 55)
        let view = Lemmy.PersonView.fake(person: person)
        let resolved = ResolvedLemmyObject(
            response: .person(view),
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
        let post = Lemmy.Post.fake(creator: .fake, community: .fake, id: 42)
        let comment = Lemmy.Comment.fake(
            id: 7,
            post: post,
            creator: .fake,
            parent: .root
        )
        let view = Lemmy.CommentView.fake(
            comment: comment,
            creator: .fake,
            post: post,
            community: .fake,
            childCount: 0
        )
        let resolved = ResolvedLemmyObject(
            response: .comment(view),
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
