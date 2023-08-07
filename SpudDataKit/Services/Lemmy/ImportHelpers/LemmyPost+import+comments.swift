//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreData
import Foundation
import os.log
import LemmyKit

private let logger = Logger(.lemmyService)

extension LemmyPost {
    func upsert(comments: [CommentView], for sortType: CommentSortType) {
        guard let context = managedObjectContext else {
            assertionFailure()
            return
        }

        guard !comments.isEmpty else {
            return
        }

        // TODO: should we update the Post itself with latest (partial) data
        //       from comments[0].post which is Post, not PostView.

        updatedAt = Date()

        // delete existing comment elements for the post
        let request = LemmyCommentElement.fetchForDeletion(postObjectId: objectID, sortType: sortType)
        do {
            let elements = try context.fetch(request)
            elements.forEach { context.delete($0) }
        } catch {
            logger.error("""
                Failed to fetch comment elements (for post \(self.postId, privacy: .public) \
                for deletion: \(error.localizedDescription, privacy: .public)
                """)
            assertionFailure()
        }

        let commentsWithMissingChildren = LemmyCommentImportHelper
            .findCommentsWithMissingChildren(comments)
            .map(\.comment.id)

        let orderedComments = LemmyCommentImportHelper.sort(comments: comments)

        // insert fetched comments

        var elementIndex: Int64 = 0

        orderedComments.forEach { commentView in
            let commentPath = CommentPath(path: commentView.comment.path)

            if let newComment = LemmyComment.upsert(commentView, post: self, in: context) {
                newComment.post = self

                let newCommentElement = LemmyCommentElement(context: context)
                newCommentElement.index = elementIndex
                newCommentElement.depth = Int16(commentPath.depth)
                newCommentElement.sortType = sortType
                newCommentElement.post = self

                newCommentElement.comment = newComment

                elementIndex += 1
            }

            if commentsWithMissingChildren.contains(commentView.comment.id) {
                let newCommentElement = LemmyCommentElement(context: context)
                newCommentElement.index = elementIndex
                newCommentElement.depth = Int16(commentPath.depth + 1)
                newCommentElement.sortType = sortType
                newCommentElement.post = self

                newCommentElement.moreParentId = commentView.comment.id
                newCommentElement.moreChildCount = commentView.counts.child_count

                elementIndex += 1
            }
        }
    }
}
