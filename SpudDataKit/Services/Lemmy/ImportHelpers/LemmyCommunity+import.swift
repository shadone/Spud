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

extension LemmyCommunity {
    convenience init(
        _ model: Components.Schemas.Community,
        account: LemmyAccount,
        in context: NSManagedObjectContext
    ) {
        self.init(context: context)

        // 1. Set relationships
        self.account = account

        // 2. Set own properties
        communityId = model.id

        // 3. Inflate object from a model
        set(from: model)

        // 4. Set meta properties
        createdAt = Date()
        updatedAt = createdAt
    }

    private func createCommunityInfo(
        in context: NSManagedObjectContext
    ) -> LemmyCommunityInfo {
        let communityInfo = LemmyCommunityInfo(in: context)

        communityInfo.community = self

        return communityInfo
    }

    /// Partial update of the ``LemmyCommunity``.
    ///
    /// This is generally called when updating community from a list of posts that only has partial data - i.e. ``Community`` but not
    /// full ``CommunityView``.
    func set(from model: Components.Schemas.Community) {
        guard let context = managedObjectContext else {
            logger.assertionFailure()
            return
        }

        assert(communityId == model.id)

        let communityInfo = communityInfo ?? createCommunityInfo(in: context)
        communityInfo.set(from: model)
    }

    /// Updates community info from the full ``CommunityView`` object.
    func set(from model: Components.Schemas.CommunityView) {
        guard let context = managedObjectContext else {
            logger.assertionFailure()
            return
        }

        assert(communityId == model.community.id)

        let communityInfo = communityInfo ?? createCommunityInfo(in: context)
        communityInfo.set(from: model)

        updatedAt = Date()
    }

    static func upsert(
        _ model: Components.Schemas.Community,
        account: LemmyAccount,
        in context: NSManagedObjectContext
    ) -> LemmyCommunity {
        let request = LemmyCommunity.fetchRequest() as NSFetchRequest<LemmyCommunity>
        request.predicate = NSPredicate(
            format: "communityId == %d && account == %@",
            model.id, account
        )
        do {
            let results = try context.fetch(request)
            if results.isEmpty {
                return LemmyCommunity(model, account: account, in: context)
            } else {
                logger.assert(results.count == 1, "Found \(results.count) communities with id '\(model.id)'")
                let community = results[0]
                community.set(from: model)
                return community
            }
        } catch {
            logger.assertionFailure("""
                Failed to fetch community for upserting: \
                \(String(describing: error))
                """)
            return LemmyCommunity(model, account: account, in: context)
        }
    }
}
