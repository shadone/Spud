//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

public extension CommunityListRow {
    /// Builds a Discover row from a live Lemmy ``Components/Schemas/CommunityView``
    /// (e.g. the result of `/api/v3/community/list`). Used when the bundled
    /// Explorer directory has no communities for an instance — most notably a
    /// remote/synthesized instance resolved live via `/api/v3/site` — so the
    /// instance screen can show its communities fetched from the server instead
    /// of an empty list.
    ///
    /// The home instance host is derived from the community's federated
    /// `actor_id` (e.g. `https://lemmy.world/c/technology` -> `lemmy.world`),
    /// matching how every other read-side helper extracts a host from an actor
    /// id. The dedup fields (`alsoOnServerCount`, `groupTotalSubscribers`) stay
    /// zero — a live single-instance fetch is not de-duplicated across servers.
    init(communityView view: Components.Schemas.CommunityView) {
        let community = view.community
        let counts = view.counts
        let host = URL(string: community.actor_id)?.host ?? ""

        self.init(
            // No stable directory id for a live row; the actor id is the
            // identity, so hash it into the Int64 id space for `Identifiable`.
            id: Int64(community.actor_id.hashValue),
            communityUrl: community.actor_id,
            instanceHost: host,
            name: community.name,
            title: community.title,
            descriptionText: community.description,
            iconUrl: community.icon.flatMap(URL.init(string:)),
            isNsfw: community.nsfw,
            isSuspicious: false,
            numberOfSubscribers: counts.subscribers,
            numberOfPosts: counts.posts,
            numberOfComments: counts.comments,
            usersActiveWeek: counts.users_active_week,
            usersActiveMonth: counts.users_active_month,
            score: Double(counts.subscribers),
            publishedAt: community.published
        )
    }
}
