//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

public extension ExplorerInstanceRecord {
    /// Builds a directory-shaped record from a live `/api/v3/site`
    /// (`GetSiteResponse`) probe of an arbitrary host.
    ///
    /// Used to open the in-app instance screen for a Lemmy-API-compatible
    /// instance (including PieFed) that is not in the bundled Lemmy Explorer
    /// directory. The header / stats / about sections read directly off this
    /// record, so every field they consume is mapped from the response;
    /// directory-only fields with no `/api/v3/site` analogue (uptime, latency,
    /// Explorer score, federation block counts) are left at sensible defaults.
    ///
    /// This is a pure transform: it has no `id` (never persisted to the curated
    /// `explorerInstance` table) and performs no I/O.
    static func synthesized(
        from response: Components.Schemas.GetSiteResponse,
        host: String
    ) -> ExplorerInstanceRecord {
        let view = response.site_view
        let site = view.site
        let localSite = view.local_site
        let counts = view.counts

        let regMode: Int64
        switch localSite.registration_mode {
        case .Closed:
            regMode = Int64(ExplorerRegistrationMode.closed.rawValue)
        case .RequireApplication:
            regMode = Int64(ExplorerRegistrationMode.requireApplication.rawValue)
        case .Open:
            regMode = Int64(ExplorerRegistrationMode.open.rawValue)
        }

        return ExplorerInstanceRecord(
            id: nil,
            baseurl: host,
            url: site.actor_id,
            name: site.name,
            descriptionText: site.description,
            version: response.version,
            usersTotal: Int64(counts.users),
            usersActiveMonth: Int64(counts.users_active_month),
            usersActiveHalfYear: Int64(counts.users_active_half_year),
            numberOfCommunities: Int64(counts.communities),
            numberOfPosts: Int64(counts.posts),
            numberOfComments: Int64(counts.comments),
            uptimeAllTime: nil,
            latency: nil,
            uptimeStatus: nil,
            regMode: regMode,
            isOpenRegistration: localSite.registration_mode == .Open,
            isNsfw: localSite.enable_nsfw,
            allowsDownvotes: localSite.enable_downvotes,
            isPrivate: localSite.private_instance,
            federationEnabled: localSite.federation_enabled,
            score: 0,
            isSuspicious: false,
            iconUrl: site.icon,
            bannerUrl: site.banner,
            langs: nil,
            tags: nil,
            blocksIncoming: nil,
            blocksOutgoing: nil,
            updatedAt: Date()
        )
    }
}
