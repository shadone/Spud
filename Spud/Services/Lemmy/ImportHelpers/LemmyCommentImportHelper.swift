//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

struct LemmyCommentImportHelper {
    /// Find incomplete comment trees.
    ///
    /// We want to find which comment tree we do not have full data on.
    /// The result is the list of most nested comments that we lack children on
    /// aka comments with missing children.
    static func findCommentsWithMissingChildren(_ comments: [CommentView]) -> [CommentView] {
        guard !comments.isEmpty else {
            return []
        }

        // sort by path string
        let commentsByPath = comments.sorted { $0.comment.path < $1.comment.path }

        var commentsWithMissingChildren: [CommentView] = []

        var previous: CommentView = comments[0]
        for i in 1..<commentsByPath.count - 1 {
            let comment = commentsByPath[i]

            if comment.comment.path.starts(with: previous.comment.path) {
                previous = comment
                continue
            }

            // previous comment is the last on in the tree that we have.
            // check if it claims to have more children that we haven't fetched yet.
            if previous.counts.child_count > 0 {
                commentsWithMissingChildren.append(previous)
            }

            previous = comment
        }

        let last = comments.last!
        // at last check the very last comment in case it also lacks children.
        if last.counts.child_count > 0 {
            commentsWithMissingChildren.append(last)
        }

        return commentsWithMissingChildren
    }
}
