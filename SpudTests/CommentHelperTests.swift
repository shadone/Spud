//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
import LemmyKit
@testable import Spud

class CommentHelperTests: XCTestCase {
    func testExample() throws {
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
}
