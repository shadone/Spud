//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

enum LemmyCommentImportHelper {
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

        if commentsByPath.count > 1 {
            var previous: CommentView = commentsByPath[0]
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
        }

        let last = commentsByPath.last!
        // at last check the very last comment in case it also lacks children.
        if last.counts.child_count > 0 {
            commentsWithMissingChildren.append(last)
        }

        return commentsWithMissingChildren
    }

    /// Sort the comments we received from server in an order they can be presented in a flat list (e.g. UITableView)
    ///
    /// The list of comments we get from the api is only partially ordered -
    /// only the comments on the same depth are ordered, but the order of comments of varying
    /// depth is undefined.
    ///
    /// For example, here are possible comments path we get:
    /// ```
    /// 0.123
    /// 0.129
    /// 0.245
    /// 0.249
    /// 0.245.987
    /// 0.123.789
    /// 0.123.222
    /// 0.123.789.555
    /// 0.123.222.456
    /// ```
    ///
    /// And here is the order we need:
    /// ```
    /// 0.123
    /// 0.123.789
    /// 0.123.789.555
    /// 0.123.222
    /// 0.123.222.456
    /// 0.129
    /// 0.245
    /// 0.245.987
    /// 0.249
    /// ```
    static func sort(comments: [CommentView]) -> [CommentView] {
        // build a comment tree
        class CommentNode {
            let id: CommentId
            var children: [CommentNode]

            init(id: CommentId, children: [CommentNode] = []) {
                self.id = id
                self.children = children
            }
        }
        var commentNodeById: [CommentId: CommentNode] = [:]

        // TODO: we could optimize for memory here and store index into `comments` instead.
        var commentViewById: [CommentId: CommentView] = [:]
        let root = CommentNode(id: 0)
        for commentView in comments {
            let commentId = commentView.comment.id
            let node = CommentNode(id: commentId)

            commentViewById[commentId] = commentView
            commentNodeById[commentId] = node

            let path = CommentPath(path: commentView.comment.path)
            guard let parentCommentId = path.parent else {
                root.children.append(node)
                continue
            }

            let parentNode = commentNodeById[parentCommentId] ?? CommentNode(id: parentCommentId)
            commentNodeById[parentNode.id] = parentNode
            parentNode.children.append(node)
        }

        // now flatten the comment tree into a list
        var orderedComments: [CommentView] = []
        func visit(_ commentNode: CommentNode) {
            let commentView = commentViewById[commentNode.id]!
            orderedComments.append(commentView)
            for child in commentNode.children {
                visit(child)
            }
        }
        for commentNode in root.children {
            visit(commentNode)
        }

        return orderedComments
    }
}
