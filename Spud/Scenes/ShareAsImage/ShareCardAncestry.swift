//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit

/// Pure ancestor-chain walk over `PostDetailViewModel.orderedComments`, used
/// by the post-detail comment menu to build a comment's chain for
/// ``ShareCardContent/init(comment:ancestors:header:permalink:)``.
///
/// Same backward, strictly-decreasing-depth scan as
/// `CommentCollapseState.collapsedAncestors(of:in:collapsedIds:)`
/// (`SpudDataKit/Services/AppDatabase/CommentCollapseState.swift`), but
/// unfiltered: it returns EVERY ancestor row, not just the ones a
/// `collapsedIds` set happens to mark collapsed, because the share card
/// needs the comment's whole visible lineage, not a collapse-bookkeeping
/// subset. Deliberately implemented here rather than added to
/// `CommentCollapseState` itself — that type owns collapse state, not
/// sharing, and this helper has nothing to do with collapse/expand.
@MainActor
enum ShareCardAncestry {
    /// Returns the ordered ancestor chain of the comment `elementId`,
    /// root-most first, so ``ShareCardContent``'s comment builder can append
    /// the shared comment as the chain's final (destination) element with no
    /// further reordering. Empty when `elementId` isn't found in `ordered`,
    /// or the comment has no ancestors (it's already a root/depth-1
    /// comment).
    static func ancestors(
        of elementId: Int64,
        in ordered: [PostDetailCommentRow]
    ) -> [PostDetailCommentRow] {
        guard let startIndex = ordered.firstIndex(where: { $0.id == elementId }) else {
            return []
        }

        var result: [PostDetailCommentRow] = []
        var ancestorDepth = ordered[startIndex].depth
        var index = startIndex - 1
        while index >= 0 {
            let row = ordered[index]
            if row.depth < ancestorDepth {
                result.append(row)
                ancestorDepth = row.depth
                if ancestorDepth <= 1 { break }
            }
            index -= 1
        }
        return result.reversed()
    }
}
