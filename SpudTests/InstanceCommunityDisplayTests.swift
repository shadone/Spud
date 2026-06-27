//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import Testing
@testable import Spud

struct InstanceCommunityDisplayTests {
    @Test
    func subtitle_showsSubscribersAndWeeklyActive() {
        let row = CommunityListRow(
            id: 1, communityUrl: "https://lemmy.world/c/technology",
            instanceHost: "lemmy.world", name: "technology", title: "Technology",
            numberOfSubscribers: 286_000, usersActiveWeek: 1200
        )
        #expect(InstanceCommunityDisplay.subtitle(for: row) == "286K subscribers · 1.2K/wk")
    }

    @Test
    func subtitle_degradesWeeklyActiveToDash() {
        let row = CommunityListRow(
            id: 1, communityUrl: "https://x/c/y", instanceHost: "x",
            name: "y", numberOfSubscribers: 0, usersActiveWeek: 0
        )
        #expect(InstanceCommunityDisplay.subtitle(for: row) == "— subscribers · —/wk")
    }
}
