//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SpudUtilKit
import XCTest
@testable import SpudDataKit

final class LemmyServiceResolveObjectTests: XCTestCase {
    private let home = InstanceActorId(from: "https://lemmy.world")!

    func test_mapsPostResponse_toPostCaseWithHomeInstance() {
        var post = Components.Schemas.Post.fake(creator: .fake, community: .fake)
        post.id = 77
        let view = Components.Schemas.PostView.fake(post: post, creator: .fake, community: .fake)
        let resolved = ResolvedLemmyObject(
            response: Components.Schemas.ResolveObjectResponse(post: view),
            homeInstance: home
        )
        guard case let .post(postId, instance) = resolved else {
            return XCTFail("expected .post")
        }
        XCTAssertEqual(postId, 77)
        XCTAssertEqual(instance.host, "lemmy.world")
    }

    func test_mapsCommunityResponse_toCommunityCaseFromActorId() {
        var community = Components.Schemas.Community.fake
        community.name = "technology"
        community.actor_id = "https://beehaw.org/c/technology"
        let view = Components.Schemas.CommunityView.fake(community: community)
        let resolved = ResolvedLemmyObject(
            response: Components.Schemas.ResolveObjectResponse(community: view),
            homeInstance: home
        )
        guard case let .community(name, instance) = resolved else {
            return XCTFail("expected .community")
        }
        XCTAssertEqual(name, "technology")
        XCTAssertEqual(instance.host, "beehaw.org")
    }

    func test_emptyResponse_isUnresolved() {
        let resolved = ResolvedLemmyObject(
            response: Components.Schemas.ResolveObjectResponse(),
            homeInstance: home
        )
        guard case .unresolved = resolved else {
            return XCTFail("expected .unresolved")
        }
    }

    func test_mapsPersonResponse_toPersonCase() {
        var person = Components.Schemas.Person.fake
        person.id = 55
        let view = Components.Schemas.PersonView.fake(person: person)
        let resolved = ResolvedLemmyObject(
            response: Components.Schemas.ResolveObjectResponse(person: view),
            homeInstance: home
        )
        guard case let .person(personId, instance) = resolved else {
            return XCTFail("expected .person")
        }
        XCTAssertEqual(personId, 55)
        XCTAssertEqual(instance.host, "lemmy.world")
    }

    func test_mapsCommentResponse_toCommentCaseWithPostAndCommentIds() {
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
            return XCTFail("expected .comment")
        }
        XCTAssertEqual(postId, 42)
        XCTAssertEqual(commentId, 7)
        XCTAssertEqual(instance.host, "lemmy.world")
    }
}
