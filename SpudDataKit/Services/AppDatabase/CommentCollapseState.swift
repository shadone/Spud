//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Pure, UIKit-free computation of the visible comment tree given a set of
/// collapsed comment element ids.
///
/// Collapse is a *client-side view concern*: the full ordered comment tree is
/// produced by `observePostDetailComments` and never mutated. This helper
/// filters that ordered list down to the rows that should currently be visible
/// and reports, for each collapsed parent, how many descendants it is hiding so
/// the cell can show a "+N" badge.
///
/// The comment list is a pre-order flattening: a comment at array index `i`
/// with `depth == d` owns every following row, in order, until the next row
/// whose `depth <= d`. "Load more" placeholders sit one level deeper than the
/// parent they belong to, so they are treated as ordinary descendants and are
/// hidden when an ancestor collapses.
public enum CommentCollapseState {
    /// The result of filtering an ordered comment list against a collapsed set.
    public struct VisibleTree: Equatable, Sendable {
        /// The rows that should be rendered, in display order. Descendants of a
        /// collapsed comment are removed; the collapsed comment itself stays.
        public let rows: [PostDetailCommentRow]

        /// For each *collapsed and visible* comment element id, the number of
        /// descendant rows it is currently hiding. Used to render the "+N"
        /// badge. Comments that are themselves hidden (because an ancestor is
        /// collapsed) are not included.
        public let collapsedDescendantCounts: [Int64: Int]

        public init(
            rows: [PostDetailCommentRow],
            collapsedDescendantCounts: [Int64: Int]
        ) {
            self.rows = rows
            self.collapsedDescendantCounts = collapsedDescendantCounts
        }
    }

    /// Computes the visible subset of `orderedComments` given `collapsedIds`.
    ///
    /// - Parameters:
    ///   - orderedComments: the full comment tree in pre-order display order
    ///     (as emitted by `observePostDetailComments`).
    ///   - collapsedIds: element ids (`PostDetailCommentRow.id`) whose subtrees
    ///     should be hidden.
    /// - Returns: the visible rows and the per-parent hidden-descendant counts.
    public static func visibleTree(
        orderedComments: [PostDetailCommentRow],
        collapsedIds: Set<Int64>
    ) -> VisibleTree {
        var visibleRows: [PostDetailCommentRow] = []
        visibleRows.reserveCapacity(orderedComments.count)

        var collapsedCounts: [Int64: Int] = [:]

        // The depth of the shallowest currently-active collapsed ancestor.
        // While we are inside a collapsed subtree, every row deeper than this
        // is hidden. `nil` means we are not inside any collapsed subtree.
        var hidingBelowDepth: Int64?

        // Stack of (elementId, depth) for collapsed comments that are
        // themselves visible and still accumulating descendants.
        var openCollapsedParents: [(id: Int64, depth: Int64)] = []

        for row in orderedComments {
            // Leaving any collapsed subtree(s) we are no longer inside of:
            // pop parents whose subtree this row is not part of.
            while let parent = openCollapsedParents.last, row.depth <= parent.depth {
                openCollapsedParents.removeLast()
            }
            if let depth = hidingBelowDepth, row.depth <= depth {
                hidingBelowDepth = nil
            }

            let isHidden = hidingBelowDepth != nil

            if !isHidden {
                visibleRows.append(row)
            }

            // Every row that is a descendant of a still-open collapsed parent
            // counts toward that parent's badge, whether or not it is itself
            // hidden (descendants of nested collapsed nodes still count).
            for parent in openCollapsedParents {
                collapsedCounts[parent.id, default: 0] += 1
            }

            // If this (visible) row is collapsed, start hiding its descendants.
            if !isHidden, collapsedIds.contains(row.id) {
                if hidingBelowDepth == nil {
                    hidingBelowDepth = row.depth
                }
                openCollapsedParents.append((id: row.id, depth: row.depth))
                collapsedCounts[row.id] = 0
            }
        }

        return VisibleTree(
            rows: visibleRows,
            collapsedDescendantCounts: collapsedCounts
        )
    }

    /// Returns the element ids of every descendant of `elementId` in
    /// `orderedComments`. Useful when collapsing should also drop any
    /// now-stale nested-collapse bookkeeping. Pure; order is preserved.
    public static func descendantIds(
        of elementId: Int64,
        in orderedComments: [PostDetailCommentRow]
    ) -> [Int64] {
        guard let startIndex = orderedComments.firstIndex(where: { $0.id == elementId }) else {
            return []
        }
        let parentDepth = orderedComments[startIndex].depth
        var result: [Int64] = []
        var index = orderedComments.index(after: startIndex)
        while index < orderedComments.count, orderedComments[index].depth > parentDepth {
            result.append(orderedComments[index].id)
            index = orderedComments.index(after: index)
        }
        return result
    }
}
