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

extension LemmyFeed {
    func append(contentsOf postViews: [PostView]) {
        guard let context = managedObjectContext else {
            logger.assertionFailure()
            return
        }

        // Find activityIds that correspond to new unique posts, i.e. removing duplicates.
        let newActivityIds = Set(
            postViews.map(\.post.ap_id)
        )
        .subtracting(postActivityIds)

        // Split all incoming postViews into those that are new and those that are duplicates.
        var newPostViews: [PostView] = []
        var existingPostViews: [PostView] = []
        for postView in postViews {
            if newActivityIds.contains(postView.post.ap_id) {
                newPostViews.append(postView)
            } else {
                existingPostViews.append(postView)
            }
        }

        postActivityIds.formUnion(newActivityIds)

        // Append page with new posts
        let page = LemmyPage(
            newPostViews,
            index: Int16(pages.count),
            account: account,
            in: context
        )
        addToPages(page)

        // Update existing posts with latest PostView info that we just got.
        for postView in existingPostViews {
            _ = LemmyPost.upsert(postView, account: account, in: context)
        }
    }
}
