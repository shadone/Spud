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
    static func findCommentsWithMissingChildren(
        _ comments: [Lemmy.CommentView]
    ) -> [Lemmy.CommentView] {
        guard !comments.isEmpty else {
            return []
        }

        // sort by path string
        let commentsByPath = comments.sorted { $0.comment.path < $1.comment.path }

        var commentsWithMissingChildren: [Lemmy.CommentView] = []

        if commentsByPath.count > 1 {
            var previous = commentsByPath[0]
            for i in 1..<commentsByPath.count - 1 {
                let comment = commentsByPath[i]

                if comment.comment.path.starts(with: previous.comment.path) {
                    previous = comment
                    continue
                }

                // previous comment is the last on in the tree that we have.
                // check if it claims to have more children that we haven't fetched yet.
                if previous.comment.childCount > 0 {
                    commentsWithMissingChildren.append(previous)
                }

                previous = comment
            }
        }

        let last = commentsByPath.last!
        // at last check the very last comment in case it also lacks children.
        if last.comment.childCount > 0 {
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
    /// The server's listing is a PARTIAL slice of the tree — it is bounded by
    /// `limit`, and by `max_depth` when a tree is requested — so a response can
    /// legitimately contain a comment whose ancestors were never fetched. Such a
    /// comment is threaded as a display root rather than dropped: rendering it
    /// slightly out of context beats a post whose header claims N comments and
    /// whose body shows none. (This is defense in depth — with `max_depth` on the
    /// request the tree comes back complete down to the depth cutoff, so orphans
    /// should not normally occur.)
    static func sort(
        comments: [Lemmy.CommentView]
    ) -> [Lemmy.CommentView] {
        // build a comment tree
        class CommentNode {
            let id: Lemmy.CommentID
            var children: [CommentNode]

            init(id: Lemmy.CommentID, children: [CommentNode] = []) {
                self.id = id
                self.children = children
            }
        }

        // TODO: we could optimize for memory here and store index into `comments` instead.
        var commentViewById: [Lemmy.CommentID: Lemmy.CommentView] = [:]
        for commentView in comments {
            // The neutral `Comment.id` is `Int64`; the id-vocabulary type is the
            // narrower generated `CommentID` (`Int32`), so narrow here.
            commentViewById[Lemmy.CommentID(commentView.comment.id)] = commentView
        }

        // A comment's parent may appear anywhere in the response — the listing is
        // only partially ordered — so nodes are looked up (and created on demand)
        // rather than assumed to already exist. Creating the parent's node here
        // must NOT replace one a child already attached itself to.
        var commentNodeById: [Lemmy.CommentID: CommentNode] = [:]
        func node(for id: Lemmy.CommentID) -> CommentNode {
            if let existing = commentNodeById[id] {
                return existing
            }
            let created = CommentNode(id: id)
            commentNodeById[id] = created
            return created
        }

        let root = CommentNode(id: 0)
        for commentView in comments {
            let commentId = Lemmy.CommentID(commentView.comment.id)
            let commentNode = node(for: commentId)

            let path = CommentPath(path: commentView.comment.path)
            guard
                let parentCommentId = path.parent,
                commentViewById[parentCommentId] != nil
            else {
                // Top-level, or an orphan whose parent was not in this response.
                root.children.append(commentNode)
                continue
            }

            node(for: parentCommentId).children.append(commentNode)
        }

        // now flatten the comment tree into a list
        var orderedComments: [Lemmy.CommentView] = []
        var visited: Set<Lemmy.CommentID> = []
        func visit(_ commentNode: CommentNode) {
            // A malformed path (a cycle, or a comment listed twice) must not
            // recurse forever or duplicate a row.
            guard visited.insert(commentNode.id).inserted else { return }
            guard let commentView = commentViewById[commentNode.id] else { return }
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
