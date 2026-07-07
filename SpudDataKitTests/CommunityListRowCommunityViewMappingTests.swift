//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import Testing
@testable import SpudDataKit

/// Covers the pure ``CommunityListRow/init(communityView:)`` mapping used to
/// render an instance's communities fetched live (`/api/v3/community/list`)
/// when the bundled Explorer directory has none.
struct CommunityListRowCommunityViewMappingTests {
    @Test
    func mapsCoreFieldsFromCommunityView() {
        let community = Lemmy.Community(
            id: 42,
            name: "technology",
            title: "Technology",
            description: "All things tech",
            removed: false,
            published: Date(timeIntervalSince1970: 1_700_000_000),
            updated: nil,
            deleted: false,
            nsfw: false,
            actor_id: "https://lemmy.world/c/technology",
            local: true,
            icon: "https://lemmy.world/pictrs/image/icon.png",
            banner: nil,
            hidden: false,
            posting_restricted_to_mods: false,
            instance_id: 1,
            visibility: .Public
        )
        let counts = Lemmy.CommunityAggregates.fake(
            communityId: 42,
            subscribers: 12345,
            posts: 678,
            comments: 9012
        )
        let view = Lemmy.CommunityView.fake(community: community, counts: counts)

        let row = CommunityListRow(communityView: view)

        #expect(row.name == "technology")
        #expect(row.title == "Technology")
        #expect(row.descriptionText == "All things tech")
        #expect(row.instanceHost == "lemmy.world")
        #expect(row.communityUrl == "https://lemmy.world/c/technology")
        #expect(row.iconUrl == URL(string: "https://lemmy.world/pictrs/image/icon.png"))
        #expect(row.numberOfSubscribers == 12345)
        #expect(row.numberOfPosts == 678)
        #expect(row.numberOfComments == 9012)
        #expect(row.isNsfw == false)
        #expect(row.publishedAt == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test
    func derivesHostFromActorIdForRemoteCommunity() {
        let community = Lemmy.Community(
            id: 7,
            name: "asklemmy",
            title: "Ask Lemmy",
            description: nil,
            removed: false,
            published: Date(timeIntervalSince1970: 1_680_000_000),
            updated: nil,
            deleted: false,
            nsfw: true,
            actor_id: "https://fedinsfw.app/c/asklemmy",
            local: false,
            icon: nil,
            banner: nil,
            hidden: false,
            posting_restricted_to_mods: false,
            instance_id: 2,
            visibility: .Public
        )
        let view = Lemmy.CommunityView.fake(community: community)

        let row = CommunityListRow(communityView: view)

        #expect(row.instanceHost == "fedinsfw.app")
        #expect(row.communityUrl == "https://fedinsfw.app/c/asklemmy")
        #expect(row.isNsfw == true)
        #expect(row.iconUrl == nil)
        // displayName prefers the title over the bare name.
        #expect(row.displayName == "Ask Lemmy")
    }

    @Test
    func reflectsZeroCountsWithoutCrashing() {
        let counts = Lemmy.CommunityAggregates.fake(
            communityId: 1,
            subscribers: 0,
            posts: 0,
            comments: 0
        )
        let view = Lemmy.CommunityView.fake(counts: counts)

        let row = CommunityListRow(communityView: view)

        #expect(row.numberOfSubscribers == 0)
        #expect(row.numberOfPosts == 0)
        #expect(row.numberOfComments == 0)
        // The dedup fields are never populated for a live (non-directory) row.
        #expect(row.alsoOnServerCount == 0)
        #expect(row.groupTotalSubscribers == 0)
    }
}
