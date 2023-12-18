//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import XCTest
@testable import SpudDataKit

class CommentHelperTests: XCTestCase {
    func testFindCommentsWithMissingChildren() throws {
        let person = Person.fake
        let community = Community.fake
        let post = Post.fake(creator: person, community: community)

        let comments: [CommentView] = [
            // "0.1": 2 children
            .fake(
                comment: .fake(id: 1, post: post, creator: person, parent: .root),
                creator: person,
                post: post,
                community: community,
                childCount: 2
            ),

            // "0.1.2": no children
            .fake(
                comment: .fake(id: 2, post: post, creator: person, parent: .root.appending(1)),
                creator: person,
                post: post,
                community: community,
                childCount: 0
            ),

            // "0.1.3": no children
            .fake(
                comment: .fake(id: 3, post: post, creator: person, parent: .root.appending(1)),
                creator: person,
                post: post,
                community: community,
                childCount: 0
            ),

            // "0.4": 1 child
            .fake(
                comment: .fake(id: 4, post: post, creator: person, parent: .root),
                creator: person,
                post: post,
                community: community,
                childCount: 1
            ),

            // "0.4.5": 42 children <-- DING DING DING we are missing some here.
            .fake(
                comment: .fake(id: 5, post: post, creator: person, parent: .root.appending(4)),
                creator: person,
                post: post,
                community: community,
                childCount: 42
            ),

            // "0.6": no children
            .fake(
                comment: .fake(id: 6, post: post, creator: person, parent: .root),
                creator: person,
                post: post,
                community: community,
                childCount: 0
            ),

            // "0.7": 1 child
            .fake(
                comment: .fake(id: 7, post: post, creator: person, parent: .root),
                creator: person,
                post: post,
                community: community,
                childCount: 1
            ),

            // "0.7.8": 1 child <-- DING DING DING we are missing a child here
            .fake(
                comment: .fake(id: 8, post: post, creator: person, parent: .root.appending(7)),
                creator: person,
                post: post,
                community: community,
                childCount: 1
            ),
        ]

        let result = LemmyCommentImportHelper.findCommentsWithMissingChildren(comments)
        XCTAssertEqual(
            result.map(\.comment.path),
            [
                "0.4.5",
                "0.7.8",
            ]
        )
    }

    func testNoMissingChildren() {
        // this is a silly test that replicates one of the oldest Lemmy posts.
        // The app was crashing on parsing the comments, but in the end it was
        // something odd in the build as clean build solved it. ¯\_(ツ)_/¯
        let comments: [CommentView] = [
            CommentView(
                comment: .init(
                    id: 471_445,
                    creator_id: 21550,
                    post_id: 57679,
                    content: "XXX",
                    removed: false,
                    published: Date(timeIntervalSinceReferenceDate: 708_499_714.602),
                    updated: nil,
                    deleted: false,
                    ap_id: URL(string: "https://sh.itjust.works/comment/171885")!,
                    local: false,
                    path: "0.471445",
                    distinguished: false,
                    language_id: 0
                ),
                creator: .fake,
                post: .fake(creator: .fake, community: .fake),
                community: .fake,
                counts: .fake(commentId: 471_445, childCount: 0),
                creator_banned_from_community: false,
                creator_is_moderator: false,
                creator_is_admin: false,
                subscribed: .notSubscribed,
                saved: false,
                creator_blocked: false,
                my_vote: nil
            ),
            CommentView(
                comment: .init(
                    id: 403_426,
                    creator_id: 90452,
                    post_id: 57679,
                    content: "XXX",
                    removed: false,
                    published: Date(timeIntervalSinceReferenceDate: 709_441_501.208),
                    updated: nil,
                    deleted: false,
                    ap_id: URL(string: "https://vlemmy.net/comment/390987")!,
                    local: false,
                    path: "0.403426",
                    distinguished: false,
                    language_id: 0
                ),
                creator: .fake,
                post: .fake(creator: .fake, community: .fake),
                community: .fake,
                counts: .fake(commentId: 403_426, childCount: 0),
                creator_banned_from_community: false,
                creator_is_moderator: false,
                creator_is_admin: false,
                subscribed: .notSubscribed,
                saved: false,
                creator_blocked: false,
                my_vote: nil
            ),
            CommentView(
                comment: .init(
                    id: 907_431,
                    creator_id: 45966,
                    post_id: 57679,
                    content: "XXX",
                    removed: false,
                    published: Date(timeIntervalSinceReferenceDate: 708_459_690.855),
                    updated: nil,
                    deleted: false,
                    ap_id: URL(string: "https://lemmy.world/comment/181062")!,
                    local: false,
                    path: "0.907431",
                    distinguished: false,
                    language_id: 0
                ),
                creator: .fake,
                post: .fake(creator: .fake, community: .fake),
                community: .fake,
                counts: .fake(commentId: 907_431, childCount: 0),
                creator_banned_from_community: false,
                creator_is_moderator: false,
                creator_is_admin: false,
                subscribed: .notSubscribed,
                saved: false,
                creator_blocked: false,
                my_vote: nil
            ),
            CommentView(
                comment: .init(
                    id: 991_036,
                    creator_id: 625_723,
                    post_id: 57679,
                    content: "XXX",
                    removed: false,
                    published: Date(timeIntervalSinceReferenceDate: 710_992_247.549),
                    updated: nil,
                    deleted: false,
                    ap_id: URL(string: "https://talk.kururin.tech/comment/107365")!,
                    local: false,
                    path: "0.991036",
                    distinguished: false,
                    language_id: 0
                ),
                creator: .fake,
                post: .fake(creator: .fake, community: .fake),
                community: .fake,
                counts: .fake(commentId: 991_036, childCount: 0),
                creator_banned_from_community: false,
                creator_is_moderator: false,
                creator_is_admin: false,
                subscribed: .notSubscribed,
                saved: false,
                creator_blocked: false,
                my_vote: nil
            ),
        ]

        let result = LemmyCommentImportHelper.findCommentsWithMissingChildren(comments)
        XCTAssertEqual(
            result.map(\.comment.path),
            []
        )
    }

    func testSort() throws {
        let person = Person.fake
        let community = Community.fake
        let post = Post.fake(creator: person, community: community)

        // 0.123
        // 0.129
        // 0.245
        // 0.249
        // 0.245.987
        // 0.123.789
        // 0.123.222
        // 0.123.789.555
        // 0.123.222.456

        let comments: [CommentView] = [
            // "0.123": 4 children
            .fake(
                comment: .fake(id: 123, post: post, creator: person, parent: .root),
                creator: person,
                post: post,
                community: community,
                childCount: 4
            ),

            // "0.129": no children
            .fake(
                comment: .fake(id: 129, post: post, creator: person, parent: .root),
                creator: person,
                post: post,
                community: community,
                childCount: 0
            ),

            // "0.245": 1 child
            .fake(
                comment: .fake(id: 245, post: post, creator: person, parent: .root),
                creator: person,
                post: post,
                community: community,
                childCount: 1
            ),

            // "0.249": no child
            .fake(
                comment: .fake(id: 249, post: post, creator: person, parent: .root),
                creator: person,
                post: post,
                community: community,
                childCount: 0
            ),

            // "0.245.987": no children
            .fake(
                comment: .fake(id: 987, post: post, creator: person, parent: .root.appending(245)),
                creator: person,
                post: post,
                community: community,
                childCount: 0
            ),

            // "0.123.789": 1 child
            .fake(
                comment: .fake(id: 789, post: post, creator: person, parent: .root.appending(123)),
                creator: person,
                post: post,
                community: community,
                childCount: 1
            ),

            // "0.123.222": 1 child
            .fake(
                comment: .fake(id: 222, post: post, creator: person, parent: .root.appending(123)),
                creator: person,
                post: post,
                community: community,
                childCount: 1
            ),

            // "0.123.789.555": no children
            .fake(
                comment: .fake(id: 555, post: post, creator: person, parent: .root.appending(123).appending(789)),
                creator: person,
                post: post,
                community: community,
                childCount: 0
            ),

            // "0.123.222.456": no children
            .fake(
                comment: .fake(id: 456, post: post, creator: person, parent: .root.appending(123).appending(222)),
                creator: person,
                post: post,
                community: community,
                childCount: 0
            ),
        ]

        let sortedComments = LemmyCommentImportHelper.sort(comments: comments)
        let sortedCommentIds = sortedComments.map(\.comment.id)
        XCTAssertEqual(
            sortedCommentIds,
            [123, 789, 555, 222, 456, 129, 245, 987, 249]
        )
    }
}
