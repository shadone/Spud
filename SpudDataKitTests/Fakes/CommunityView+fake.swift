//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

extension Lemmy.CommunityView {
    static func fake(
        community: Lemmy.Community = .fake,
        subscribed: Lemmy.SubscribedType = .NotSubscribed,
        counts: Lemmy.CommunityAggregates? = nil
    ) -> Lemmy.CommunityView {
        .init(
            community: community,
            subscribed: subscribed,
            blocked: false,
            counts: counts ?? .fake(communityId: community.id),
            banned_from_community: false
        )
    }
}
