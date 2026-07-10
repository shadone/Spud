//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

public extension CommunityListRow {
    /// Build a directory row from a live Lemmy community search result, for the
    /// Discover "search the network" fallback. Returns nil when the actor id has
    /// no parseable host. No trust/ranking data is available for live results, so
    /// `isSuspicious` and `score` are left at their defaults.
    init?(searchView view: Lemmy.CommunityView) {
        let community = view.community
        guard
            let url = URL(string: community.apId),
            let host = url.host
        else { return nil }

        self.init(
            id: community.id,
            communityUrl: community.apId,
            instanceHost: host,
            name: community.name,
            title: community.title,
            descriptionText: community.sidebar,
            iconUrl: community.iconUrl.flatMap { URL(string: $0) },
            isNsfw: community.nsfw,
            isSuspicious: false,
            numberOfSubscribers: community.subscribers,
            numberOfPosts: community.posts,
            numberOfComments: community.comments,
            // The neutral Community drops active-user counts (no v4 source), so
            // the "active this week/month" figures are unavailable for live rows.
            usersActiveWeek: 0,
            usersActiveMonth: 0,
            score: 0
        )
    }
}
