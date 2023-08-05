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

extension LemmyCommunity {
    convenience init(
        _ model: Community,
        account: LemmyAccount,
        in context: NSManagedObjectContext
    ) {
        self.init(context: context)

        communityId = model.id

        set(from: model)

        createdAt = Date()
        updatedAt = createdAt

        self.account = account
    }

    private func getOrCreateCommunityInfo() -> LemmyCommunityInfo? {
        func createCommunityInfo() -> LemmyCommunityInfo? {
            guard let context = managedObjectContext else {
                assertionFailure()
                return nil
            }

            let communityInfo = LemmyCommunityInfo(in: context)
            communityInfo.community = self

            return communityInfo
        }

        guard let communityInfo else {
            communityInfo = createCommunityInfo()
            return communityInfo
        }
        return communityInfo
    }

    /// Partial update of the ``LemmyCommunity``.
    ///
    /// This is generally called when updating community from a list of posts that only has partial data - i.e. ``Community`` but not
    /// full ``CommunityView``.
    func set(from model: Community) {
        assert(communityId == model.id)

        let communityInfo = getOrCreateCommunityInfo()
        communityInfo?.set(from: model)
    }

    /// Updates community info from the full ``CommunityView`` object.
    func set(from model: CommunityView) {
        assert(communityId == model.community.id)

        let communityInfo = getOrCreateCommunityInfo()
        communityInfo?.set(from: model)

        updatedAt = Date()
    }

    static func upsert(
        _ model: Community,
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
            if results.count == 0 {
                return LemmyCommunity(model, account: account, in: context)
            } else if results.count == 1 {
                let community = results[0]
                community.set(from: model)
                return community
            } else {
                assertionFailure("Found \(results.count) communities with id '\(model.id)'")
                return results[0]
            }
        } catch {
            logger.error("""
                Failed to fetch community for upserting: \
                \(String(describing: error), privacy: .public)
                """)
            assertionFailure()
            return LemmyCommunity(model, account: account, in: context)
        }
    }
}
