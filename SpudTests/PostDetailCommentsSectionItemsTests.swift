//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import Spud

/// Covers `PostDetailViewController.commentsSectionItems(background:commentItems:)`:
/// the loading skeleton and the empty "No comments yet" state each replace the
/// comment rows with a single in-flow placeholder row while they are the active
/// background; `.hidden` (and the defensive case of `.empty` with comments somehow
/// present) passes the comment items through unchanged.
final class PostDetailCommentsSectionItemsTests: XCTestCase {
    func testSkeletonWithNoCommentsIsSingleSkeletonRow() {
        let items = PostDetailViewController.commentsSectionItems(
            background: .skeleton,
            commentItems: []
        )
        XCTAssertEqual(items, [.commentLoadingSkeleton])
    }

    // Defensive: documents the helper's contract in isolation. The production
    // caller cannot produce this state — `CommentsBackground.decide` returns
    // `.skeleton` only when there are no comments, so `commentItems` is always
    // empty in the skeleton case.
    func testSkeletonWinsOverPresentCommentItems() {
        let items = PostDetailViewController.commentsSectionItems(
            background: .skeleton,
            commentItems: [.comment(elementId: 1), .comment(elementId: 2)]
        )
        XCTAssertEqual(items, [.commentLoadingSkeleton])
    }

    func testEmptyWithNoCommentsIsSingleEmptyRow() {
        let items = PostDetailViewController.commentsSectionItems(
            background: .empty,
            commentItems: []
        )
        XCTAssertEqual(items, [.commentsEmpty])
    }

    func testHiddenPassesCommentItemsThrough() {
        let commentItems: [PostDetailViewController.Item] = [
            .comment(elementId: 1),
            .comment(elementId: 2),
        ]
        let items = PostDetailViewController.commentsSectionItems(
            background: .hidden,
            commentItems: commentItems
        )
        XCTAssertEqual(items, commentItems)
    }

    func testEmptyPassesCommentItemsThrough() {
        let commentItems: [PostDetailViewController.Item] = [
            .comment(elementId: 1),
            .comment(elementId: 2),
        ]
        let items = PostDetailViewController.commentsSectionItems(
            background: .empty,
            commentItems: commentItems
        )
        XCTAssertEqual(items, commentItems)
    }
}
