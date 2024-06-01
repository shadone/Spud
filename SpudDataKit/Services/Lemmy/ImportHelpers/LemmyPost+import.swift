//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreData
import Foundation
import LemmyKit
import OSLog

private let logger = Logger(.lemmyService)

extension LemmyPost {
    convenience init(
        _ model: Components.Schemas.PostView,
        account: LemmyAccount,
        in context: NSManagedObjectContext
    ) {
        self.init(context: context)

        // 1. Set relationships
        self.account = account

        // 2. Set own properties
        postId = model.post.id

        // 3. Inflate object from a model
        set(from: model)

        // 4. Set meta properties
        createdAt = Date()
        updatedAt = createdAt
    }

    private func createPostInfo(
        creator: Components.Schemas.Person,
        community: Components.Schemas.Community,
        in context: NSManagedObjectContext
    ) -> LemmyPostInfo {
        let creator = LemmyPerson.upsert(
            creator,
            site: account.site,
            in: context
        )

        let community = LemmyCommunity.upsert(
            community,
            account: account,
            in: context
        )

        let postInfo = LemmyPostInfo(
            creator: creator,
            community: community,
            in: context
        )

        postInfo.post = self

        return postInfo
    }

    func set(from model: Components.Schemas.PostView) {
        guard let context = managedObjectContext else {
            logger.assertionFailure()
            return
        }

        assert(postId == model.post.id)

        let postInfo = postInfo ?? createPostInfo(
            creator: model.creator,
            community: model.community,
            in: context
        )
        postInfo.set(from: model)

        updatedAt = Date()
    }

    static func upsert(
        _ model: Components.Schemas.PostView,
        account: LemmyAccount,
        in context: NSManagedObjectContext
    ) -> LemmyPost {
        let request = LemmyPost.fetchRequest() as NSFetchRequest<LemmyPost>
        request.predicate = NSPredicate(
            format: "postId == %d AND account == %@",
            model.post.id, account
        )
        do {
            let results = try context.fetch(request)
            if results.isEmpty {
                return LemmyPost(model, account: account, in: context)
            } else {
                logger.assert(results.count == 1, "Found \(results.count) posts with id '\(model.post.id)'")
                let post = results[0]
                post.set(from: model)
                return post
            }
        } catch {
            logger.assertionFailure("Failed to fetch posts for upserting: \(String(describing: error))")
            return LemmyPost(model, account: account, in: context)
        }
    }
}
