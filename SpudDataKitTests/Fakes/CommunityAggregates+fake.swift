//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

extension Components.Schemas.CommunityAggregates {
    static func fake(
        communityId: Components.Schemas.CommunityID = 1,
        subscribers: Int64 = 100,
        posts: Int64 = 50,
        comments: Int64 = 200
    ) -> Components.Schemas.CommunityAggregates {
        .init(
            community_id: communityId,
            subscribers: subscribers,
            posts: posts,
            comments: comments,
            published: Date(timeIntervalSince1970: 1_680_667_628),
            users_active_day: 1,
            users_active_week: 5,
            users_active_month: 10,
            users_active_half_year: 20,
            subscribers_local: subscribers
        )
    }
}
