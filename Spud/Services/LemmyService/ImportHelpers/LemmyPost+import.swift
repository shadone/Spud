//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreData
import Foundation
import os.log
import LemmyKit

extension LemmyPost {
    convenience init(
        _ model: PostView,
        in context: NSManagedObjectContext
    ) {
        self.init(context: context)

        set(from: model, in: context)

        createdAt = Date()
        updatedAt = createdAt
    }

    static func upsert(
        _ model: PostView,
        in context: NSManagedObjectContext
    ) -> LemmyPost {
        let request = LemmyPost.fetchRequest() as NSFetchRequest<LemmyPost>
        request.predicate = NSPredicate(format: "id == %d", model.post.id)
        do {
            let results = try context.fetch(request)
            if results.count == 0 {
                return LemmyPost(model, in: context)
            } else if results.count == 1 {
                let post = results[0]
                post.set(from: model, in: context)
                post.updatedAt = Date()
                return post
            } else {
                assertionFailure("Found \(results.count) posts with id '\(model.post.id)'")
                return results[0]
            }
        } catch {
            os_log("Failed to fetch posts for upserting: %{public}@",
                   log: .app, type: .error,
                   String(describing: error))
            assertionFailure()
            return LemmyPost(model, in: context)
        }
    }

    private func set(from model: PostView, in context: NSManagedObjectContext) {
        id = model.post.id
        title = model.post.name
        communityName = model.community.name
    }
}
