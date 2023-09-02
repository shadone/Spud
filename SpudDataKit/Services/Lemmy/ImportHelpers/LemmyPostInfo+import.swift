//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreData
import Foundation
import LemmyKit
import OSLog

private let logger = Logger(.dataStore)

extension LemmyPostInfo {
    func set(from model: PostView) {
        set(from: model.post)
        set(from: model.counts)

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

        updatedAt = Date()
    }

    private func set(from model: Post) {
        originalPostUrl = model.ap_id

        title = model.name
        body = model.body

        thumbnailUrl = model.thumbnail_url?.url

        url = model.url?.url
        urlEmbedTitle = model.embed_title
        urlEmbedDescription = model.embed_description

        published = model.published
    }

    private func set(from model: PostAggregates) {
        numberOfComments = model.comments

        score = model.score
        numberOfUpvotes = model.upvotes
        numberOfDownvotes = model.downvotes
    }
}
