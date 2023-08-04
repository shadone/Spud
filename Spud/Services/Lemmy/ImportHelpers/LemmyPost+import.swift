//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreData
import Foundation
import os.log
import LemmyKit

private let logger = Logger(.app)

extension LemmyPost {
    convenience init(
        _ model: PostView,
        account: LemmyAccount,
        in context: NSManagedObjectContext
    ) {
        self.init(context: context)

        postId = model.post.id

        set(from: model)

        createdAt = Date()
        updatedAt = createdAt

        self.account = account

        assert(postInfo != nil, "should have been created by the set()")
        postInfo?.creator = LemmyPerson.upsert(model.creator, site: account.site, in: context)
    }

    private func getOrCreatePostInfo() -> LemmyPostInfo? {
        func createPostInfo() -> LemmyPostInfo? {
            guard let context = managedObjectContext else {
                assertionFailure()
                return nil
            }

            let postInfo = LemmyPostInfo(in: context)
            postInfo.post = self

            return postInfo
        }

        guard let postInfo else {
            postInfo = createPostInfo()
            return postInfo
        }
        return postInfo
    }

    func set(from model: PostView) {
        assert(postId == model.post.id)

        let postInfo = getOrCreatePostInfo()
        assert(postInfo != nil)
        postInfo?.set(from: model)

        updatedAt = Date()
    }

    static func upsert(
        _ model: PostView,
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
            if results.count == 0 {
                return LemmyPost(model, account: account, in: context)
            } else if results.count == 1 {
                let post = results[0]
                post.set(from: model)
                return post
            } else {
                assertionFailure("Found \(results.count) posts with id '\(model.post.id)'")
                return results[0]
            }
        } catch {
            logger.error("Failed to fetch posts for upserting: \(String(describing: error), privacy: .public)")
            assertionFailure()
            return LemmyPost(model, account: account, in: context)
        }
    }
}
