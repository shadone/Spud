//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudDataKit

struct CommentCollapseStateTests {
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
            removedReason: nil,
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

    @Test
    func nothingCollapsedReturnsAllRows() {
        let tree = sampleTree()
        let result = CommentCollapseState.visibleTree(orderedComments: tree, collapsedIds: [])
        #expect(result.rows.map(\.id) == [1, 2, 3, 4, 5])
        #expect(result.collapsedDescendantCounts.isEmpty)
    }

    @Test
    func collapsingTopLevelHidesEntireSubtree() {
        let tree = sampleTree()
        let result = CommentCollapseState.visibleTree(orderedComments: tree, collapsedIds: [1])
        // Comment 1 stays visible; its descendants 2, 3, 4 are hidden; sibling 5 stays.
        #expect(result.rows.map(\.id) == [1, 5])
        #expect(result.collapsedDescendantCounts[1] == 3)
    }

    @Test
    func collapsingMidNodeHidesOnlyItsSubtree() {
        let tree = sampleTree()
        let result = CommentCollapseState.visibleTree(orderedComments: tree, collapsedIds: [2])
        // Comment 2 stays; its only descendant 3 is hidden; 1, 4, 5 stay.
        #expect(result.rows.map(\.id) == [1, 2, 4, 5])
        #expect(result.collapsedDescendantCounts[2] == 1)
    }

    @Test
    func nestedCollapseCountsAllDescendantsForOuterParent() {
        let tree = sampleTree()
        // Collapsing both 1 and 2: only 1 is visible, badge counts 2, 3, 4.
        let result = CommentCollapseState.visibleTree(orderedComments: tree, collapsedIds: [1, 2])
        #expect(result.rows.map(\.id) == [1, 5])
        #expect(result.collapsedDescendantCounts[1] == 3)
        // Comment 2 is hidden, so it has no visible badge.
        #expect(result.collapsedDescendantCounts[2] == nil)
    }

    @Test
    func loadMorePlaceholderIsHiddenWhenAncestorCollapses() {
        // 1 (1) -> 2 (2) -> [load more] (3)
        let tree = [
            row(id: 1, depth: 1),
            row(id: 2, depth: 2),
            row(id: 99, depth: 3, more: true),
        ]
        let collapsed = CommentCollapseState.visibleTree(orderedComments: tree, collapsedIds: [1])
        #expect(collapsed.rows.map(\.id) == [1])
        #expect(collapsed.collapsedDescendantCounts[1] == 2) // comment 2 + load-more row

        // When expanded the load-more row is visible and functional.
        let expanded = CommentCollapseState.visibleTree(orderedComments: tree, collapsedIds: [])
        #expect(expanded.rows.map(\.id) == [1, 2, 99])
    }

    @Test
    func descendantIds() {
        let tree = sampleTree()
        #expect(CommentCollapseState.descendantIds(of: 1, in: tree) == [2, 3, 4])
        #expect(CommentCollapseState.descendantIds(of: 2, in: tree) == [3])
        #expect(CommentCollapseState.descendantIds(of: 5, in: tree) == [])
        #expect(CommentCollapseState.descendantIds(of: 12345, in: tree) == [])
    }

    @Test
    func collapsingLeafHasNoEffectOnRowsAndZeroCount() {
        let tree = sampleTree()
        let result = CommentCollapseState.visibleTree(orderedComments: tree, collapsedIds: [3])
        #expect(result.rows.map(\.id) == [1, 2, 3, 4, 5])
        #expect(result.collapsedDescendantCounts[3] == 0)
    }

    @Test
    func collapsedNewDescendantCountsCountsOnlyNewHiddenDescendants() {
        let tree = sampleTree() // 1 > (2 > 3), 4 ; 5
        // Collapse 1; 3 and 4 are new, 2 is old. All three are hidden under 1.
        let result = CommentCollapseState.visibleTree(
            orderedComments: tree,
            collapsedIds: [1],
            newElementIds: [3, 4]
        )
        #expect(result.collapsedDescendantCounts[1] == 3)
        #expect(result.collapsedNewDescendantCounts[1] == 2)
    }

    @Test
    func collapsedNewDescendantCountsNestedCountsForOutermostVisibleParent() {
        let tree = sampleTree()
        // Collapse 1 and 2; only 3 is new. 1 is the visible parent; 2 is hidden.
        let result = CommentCollapseState.visibleTree(
            orderedComments: tree,
            collapsedIds: [1, 2],
            newElementIds: [3]
        )
        #expect(result.collapsedNewDescendantCounts[1] == 1)
        #expect(result.collapsedNewDescendantCounts[2] == nil) // hidden -> no visible badge
    }

    @Test
    func collapsedParentWithNoNewDescendantsHasNoNewCount() {
        let tree = sampleTree()
        // Collapse 1; the only new comment (5) is a sibling, not under 1.
        let result = CommentCollapseState.visibleTree(
            orderedComments: tree,
            collapsedIds: [1],
            newElementIds: [5]
        )
        #expect(result.collapsedDescendantCounts[1] == 3)
        #expect(result.collapsedNewDescendantCounts[1] == nil)
    }

    @Test
    func noNewElementIdsLeavesNewCountsEmpty() {
        let tree = sampleTree()
        let result = CommentCollapseState.visibleTree(orderedComments: tree, collapsedIds: [1])
        #expect(result.collapsedNewDescendantCounts.isEmpty)
    }

    @Test
    func collapsedAncestorsVisibleTargetReturnsEmpty() {
        let tree = sampleTree()
        #expect(
            CommentCollapseState.collapsedAncestors(of: 3, in: tree, collapsedIds: []) == []
        )
    }

    @Test
    func collapsedAncestorsSingleCollapsedParent() {
        let tree = sampleTree() // 3's ancestors are 2 (depth 2) and 1 (depth 1)
        #expect(
            CommentCollapseState.collapsedAncestors(of: 3, in: tree, collapsedIds: [1]) == [1]
        )
    }

    @Test
    func collapsedAncestorsNestedChainIsLeafToRoot() {
        let tree = sampleTree()
        // Both 1 and 2 collapsed; revealing 3 needs both, returned leaf-to-root.
        #expect(
            CommentCollapseState.collapsedAncestors(of: 3, in: tree, collapsedIds: [1, 2]) == [2, 1]
        )
    }

    @Test
    func collapsedAncestorsUnknownIdReturnsEmpty() {
        let tree = sampleTree()
        #expect(
            CommentCollapseState.collapsedAncestors(of: 999, in: tree, collapsedIds: [1]) == []
        )
    }
}
