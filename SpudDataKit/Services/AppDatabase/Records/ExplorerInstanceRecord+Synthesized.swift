//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

public extension ExplorerInstanceRecord {
    /// Builds a directory-shaped record from a live site-info
    /// (`LemmyKit.SiteInfo`) probe of an arbitrary host.
    ///
    /// Used to open the in-app instance screen for a Lemmy-API-compatible
    /// instance (including PieFed) that is not in the bundled Lemmy Explorer
    /// directory. The header / stats / about sections read directly off this
    /// record, so every field they consume is mapped from the response;
    /// directory-only fields with no site-info analogue (uptime, latency,
    /// Explorer score, federation block counts) are left at sensible defaults.
    ///
    /// This is a pure transform: it has no `id` (never persisted to the curated
    /// `explorerInstance` table) and performs no I/O.
    static func synthesized(
        from siteInfo: LemmyKit.SiteInfo,
        host: String
    ) -> ExplorerInstanceRecord {
        let site = siteInfo.site

        return ExplorerInstanceRecord(
            id: nil,
            baseurl: host,
            url: site.apId,
            name: site.name,
            descriptionText: site.summary,
            version: siteInfo.version,
            usersTotal: site.users,
            usersActiveMonth: site.usersActiveMonth,
            usersActiveHalfYear: site.usersActiveHalfYear,
            numberOfCommunities: site.communities,
            numberOfPosts: site.posts,
            numberOfComments: site.comments,
            uptimeAllTime: nil,
            latency: nil,
            uptimeStatus: nil,
            // NOTE: the neutral SiteInfo/Site carries no local-site config
            // (registration mode, NSFW, downvote, private-instance, or
            // federation flags). We genuinely don't know these from the neutral
            // surface, so registration reads as `.unknown` rather than falsely
            // "open"; the rest use benign defaults. No neutral source (Phase 6
            // follow-up).
            regMode: Int64(ExplorerRegistrationMode.unknown.rawValue),
            isOpenRegistration: false,
            isNsfw: false,
            allowsDownvotes: true,
            isPrivate: false,
            federationEnabled: true,
            score: 0,
            isSuspicious: false,
            iconUrl: site.iconUrl,
            bannerUrl: site.bannerUrl,
            langs: nil,
            tags: nil,
            blocksIncoming: nil,
            blocksOutgoing: nil,
            updatedAt: Date()
        )
    }
}
