//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreData
import Foundation
import LemmyKit
import OSLog

private let logger = Logger.lemmyService

extension LemmyComment {
    convenience init(
        _ model: Components.Schemas.CommentView,
        post: LemmyPost,
        in context: NSManagedObjectContext
    ) {
        self.init(context: context)

        set(from: model)

        createdAt = Date()
        updatedAt = createdAt

        self.post = post
        creator = LemmyPerson.upsert(model.creator, site: post.account.site, in: context)
    }

    func set(from model: Components.Schemas.CommentView) {
        localCommentId = model.comment.id
        originalCommentUrl = URL(string: model.comment.ap_id)!
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
                logger.assertionFailure("Received unexpected my_vote value '\(String(describing: model.my_vote))' for post id \(model.post.id)")
                return .neutral
            }
        }()

        published = model.comment.published

        updatedAt = Date()
    }

    static func upsert(
        _ model: Components.Schemas.CommentView,
        post: LemmyPost,
        in context: NSManagedObjectContext
    ) -> LemmyComment? {
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
                existingComment.set(from: model)
                return existingComment
            } else {
                return LemmyComment(model, post: post, in: context)
            }
        } catch {
            logger.error("""
                Failed to fetch comment \(model.comment.id, privacy: .public) for upserting: \
                \(String(describing: error), privacy: .public)
                """)
            return nil
        }
    }
}
