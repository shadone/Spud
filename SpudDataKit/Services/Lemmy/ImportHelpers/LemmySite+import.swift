//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreData
import Foundation
import LemmyKit
import OSLog
import SpudUtilKit

private let logger = Logger.dataStore

extension LemmySite {
    func upsert(
        siteInfo model: Components.Schemas.GetSiteResponse
    ) {
        guard let context = managedObjectContext else {
            logger.assertionFailure()
            return
        }

        let actorIdValue = model.site_view.site.actor_id
        let actorId = InstanceActorId(from: actorIdValue)
        assert(actorId != nil, "failed to parse actor id '\(actorIdValue)'")
        assert(
            instance.actorId == actorId,
            "\(instance.actorId) != \(String(describing: actorId))"
        )

        func createSiteInfo() -> LemmySiteInfo {
            let siteInfo = LemmySiteInfo(context: context)
            siteInfo.site = self
            siteInfo.createdAt = Date()
            return siteInfo
        }

        let siteInfo: LemmySiteInfo = siteInfo ?? createSiteInfo()

        siteInfo.name = model.site_view.site.name
        siteInfo.sidebar = model.site_view.site.sidebar
        siteInfo.descriptionText = model.site_view.site.description
        siteInfo.legalInformation = model.site_view.local_site.legal_information

        siteInfo.version = model.version

        siteInfo.bannerUrl = model.site_view.site.banner.map(LenientUrl.init)?.url
        siteInfo.iconUrl = model.site_view.site.icon.map(LenientUrl.init)?.url
        siteInfo.defaultPostListingType = model.site_view.local_site.default_post_listing_type
        siteInfo.enableDownvotes = model.site_view.local_site.enable_downvotes
        siteInfo.enableNsfw = model.site_view.local_site.enable_nsfw

        siteInfo.numberOfComments = model.site_view.counts.comments
        siteInfo.numberOfCommunities = model.site_view.counts.communities
        siteInfo.numberOfPosts = model.site_view.counts.posts
        siteInfo.numberOfUsers = model.site_view.counts.users
        siteInfo.numberOfUsersDay = model.site_view.counts.users_active_day
        siteInfo.numberOfUsersWeek = model.site_view.counts.users_active_week
        siteInfo.numberOfUsersMonth = model.site_view.counts.users_active_month
        siteInfo.numberOfUsersHalfYear = model.site_view.counts.users_active_half_year

        siteInfo.infoCreatedDate = model.site_view.local_site.published
        siteInfo.infoUpdatedDate = model.site_view.local_site.updated

        siteInfo.updatedAt = Date()
    }
}
