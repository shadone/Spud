//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import Spud

/// Covers `PostDetailViewController.commentsSectionItems(background:commentItems:)`:
/// the loading skeleton replaces the comment rows as a single in-flow row while
/// `.skeleton` is the active background; the empty/hidden placeholders draw as the
/// table background and so contribute no rows (the comment items pass through
/// unchanged).
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

    func testEmptyWithNoCommentsHasNoRows() {
        let items = PostDetailViewController.commentsSectionItems(
            background: .empty,
            commentItems: []
        )
        XCTAssertEqual(items, [])
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
