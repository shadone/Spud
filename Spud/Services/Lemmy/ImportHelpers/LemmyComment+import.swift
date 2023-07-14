//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreData
import Foundation
import LemmyKit
import os.log

extension LemmyComment {
    convenience init(
        _ model: CommentView,
        post: LemmyPost,
        in context: NSManagedObjectContext
    ) {
        self.init(context: context)

        set(model)

        self.post = post
        self.creator = LemmyPerson.upsert(model.creator, site: post.account.site, in: context)
    }

    private func set(_ model: CommentView) {
        localCommentId = model.comment.id
        originalCommentUrl = model.comment.ap_id
        body = model.comment.content

        score = model.counts.score
        numberOfUpvotes = model.counts.upvotes
        numberOfDownvotes = model.counts.downvotes

        voteStatus = {
            switch model.my_vote {
            case 1:
                return .up
            case -1:
                return .down
            case 0, nil:
                return .neutral
            default:
                assertionFailure("Received unexpected my_vote value '\(String(describing: model.my_vote))' for post id \(model.post.id)")
                return .neutral
            }
        }()

        published = model.comment.published
    }

    static func upsert(
        _ model: CommentView,
        post: LemmyPost,
        in context: NSManagedObjectContext
    ) -> LemmyComment?
    {
        let request = LemmyComment.fetchRequest() as NSFetchRequest<LemmyComment>
        request.predicate = NSPredicate(
            format: "localCommentId == %d AND post == %@",
            model.comment.id, post
        )
        request.fetchLimit = 1
        request.includesPropertyValues = false

        do {
            let results = try context.fetch(request)

            if let existingComment = results.first {
                existingComment.set(model)
                return existingComment
            } else {
                return LemmyComment(model, post: post, in: context)
            }
        } catch {
            os_log("Failed to fetch comment %{public}d for upserting: %{public}@",
                   log: .app, type: .error,
                   model.comment.id, String(describing: error))
            return nil
        }
    }
}
