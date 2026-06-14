//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import SpudDataKit

final class CommentCollapseStateTests: XCTestCase {
    /// Builds a comment row with just the fields the collapse computation reads:
    /// id, position, depth. Everything else is filler.
    private func row(id: Int64, depth: Int64, more: Bool = false) -> PostDetailCommentRow {
        PostDetailCommentRow(
            id: id,
            position: id,
            depth: depth,
            serverCommentId: more ? nil : id,
            body: more ? nil : "body \(id)",
            originalCommentUrl: more ? nil : "https://example.test/comment/\(id)",
            score: 0,
            voteStatus: nil,
            isSaved: more ? nil : false,
            isRemoved: more ? nil : false,
            isDistinguished: more ? nil : false,
            isDeleted: more ? nil : false,
            isCreatorModerator: more ? nil : false,
            isCreatorAdmin: more ? nil : false,
            isCreatorBannedFromCommunity: more ? nil : false,
            isCreatorBlocked: more ? nil : false,
            isCreatorSiteBanned: more ? nil : false,
            isCreatorBot: more ? nil : false,
            isCreatorAccountDeleted: more ? nil : false,
            published: more ? nil : Date(timeIntervalSince1970: 0),
            creatorName: more ? nil : "u\(id)",
            creatorPersonId: more ? nil : id,
            creatorInstanceActorId: more ? nil : "https://example.test",
            moreChildCount: more ? 3 : nil,
            moreParentId: more ? 1 : nil
        )
    }

    /// Tree (depth in parens):
    ///   1 (1)
    ///     2 (2)
    ///       3 (3)
    ///     4 (2)
    ///   5 (1)
    private func sampleTree() -> [PostDetailCommentRow] {
        [
            row(id: 1, depth: 1),
            row(id: 2, depth: 2),
            row(id: 3, depth: 3),
            row(id: 4, depth: 2),
            row(id: 5, depth: 1),
        ]
    }

    func testNothingCollapsedReturnsAllRows() {
        let tree = sampleTree()
        let result = CommentCollapseState.visibleTree(orderedComments: tree, collapsedIds: [])
        XCTAssertEqual(result.rows.map(\.id), [1, 2, 3, 4, 5])
        XCTAssertTrue(result.collapsedDescendantCounts.isEmpty)
    }

    func testCollapsingTopLevelHidesEntireSubtree() {
        let tree = sampleTree()
        let result = CommentCollapseState.visibleTree(orderedComments: tree, collapsedIds: [1])
        // Comment 1 stays visible; its descendants 2, 3, 4 are hidden; sibling 5 stays.
        XCTAssertEqual(result.rows.map(\.id), [1, 5])
        XCTAssertEqual(result.collapsedDescendantCounts[1], 3)
    }

    func testCollapsingMidNodeHidesOnlyItsSubtree() {
        let tree = sampleTree()
        let result = CommentCollapseState.visibleTree(orderedComments: tree, collapsedIds: [2])
        // Comment 2 stays; its only descendant 3 is hidden; 1, 4, 5 stay.
        XCTAssertEqual(result.rows.map(\.id), [1, 2, 4, 5])
        XCTAssertEqual(result.collapsedDescendantCounts[2], 1)
    }

    func testNestedCollapseCountsAllDescendantsForOuterParent() {
        let tree = sampleTree()
        // Collapsing both 1 and 2: only 1 is visible, badge counts 2, 3, 4.
        let result = CommentCollapseState.visibleTree(orderedComments: tree, collapsedIds: [1, 2])
        XCTAssertEqual(result.rows.map(\.id), [1, 5])
        XCTAssertEqual(result.collapsedDescendantCounts[1], 3)
        // Comment 2 is hidden, so it has no visible badge.
        XCTAssertNil(result.collapsedDescendantCounts[2])
    }

    func testLoadMorePlaceholderIsHiddenWhenAncestorCollapses() {
        // 1 (1) -> 2 (2) -> [load more] (3)
        let tree = [
            row(id: 1, depth: 1),
            row(id: 2, depth: 2),
            row(id: 99, depth: 3, more: true),
        ]
        let collapsed = CommentCollapseState.visibleTree(orderedComments: tree, collapsedIds: [1])
        XCTAssertEqual(collapsed.rows.map(\.id), [1])
        XCTAssertEqual(collapsed.collapsedDescendantCounts[1], 2) // comment 2 + load-more row

        // When expanded the load-more row is visible and functional.
        let expanded = CommentCollapseState.visibleTree(orderedComments: tree, collapsedIds: [])
        XCTAssertEqual(expanded.rows.map(\.id), [1, 2, 99])
    }

    func testDescendantIds() {
        let tree = sampleTree()
        XCTAssertEqual(CommentCollapseState.descendantIds(of: 1, in: tree), [2, 3, 4])
        XCTAssertEqual(CommentCollapseState.descendantIds(of: 2, in: tree), [3])
        XCTAssertEqual(CommentCollapseState.descendantIds(of: 5, in: tree), [])
        XCTAssertEqual(CommentCollapseState.descendantIds(of: 12345, in: tree), [])
    }

    func testCollapsingLeafHasNoEffectOnRowsAndZeroCount() {
        let tree = sampleTree()
        let result = CommentCollapseState.visibleTree(orderedComments: tree, collapsedIds: [3])
        XCTAssertEqual(result.rows.map(\.id), [1, 2, 3, 4, 5])
        XCTAssertEqual(result.collapsedDescendantCounts[3], 0)
    }
}
