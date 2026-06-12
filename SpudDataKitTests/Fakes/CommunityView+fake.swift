//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

extension Components.Schemas.CommunityView {
    static func fake(
        community: Components.Schemas.Community = .fake,
        subscribed: Components.Schemas.SubscribedType = .NotSubscribed,
        counts: Components.Schemas.CommunityAggregates? = nil
    ) -> Components.Schemas.CommunityView {
        .init(
            community: community,
            subscribed: subscribed,
            blocked: false,
            counts: counts ?? .fake(communityId: community.id),
            banned_from_community: false
        )
    }
}
