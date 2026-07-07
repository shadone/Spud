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
            let url = URL(string: community.actor_id),
            let host = url.host
        else { return nil }

        self.init(
            id: Int64(community.id),
            communityUrl: community.actor_id,
            instanceHost: host,
            name: community.name,
            title: community.title,
            descriptionText: community.description,
            iconUrl: community.icon.flatMap { URL(string: $0) },
            isNsfw: community.nsfw,
            isSuspicious: false,
            numberOfSubscribers: view.counts.subscribers,
            numberOfPosts: view.counts.posts,
            numberOfComments: view.counts.comments,
            usersActiveWeek: view.counts.users_active_week,
            usersActiveMonth: view.counts.users_active_month,
            score: 0
        )
    }
}
