//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import LemmyKit
@testable import Spud

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
            result.map { $0.comment.path },
            [
                "0.4.5",
                "0.7.8",
            ]
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
        let sortedCommentIds = sortedComments.map { $0.comment.id }
        XCTAssertEqual(
            sortedCommentIds,
            [123, 789, 555, 222, 456, 129, 245, 987, 249]
        )
    }
}
