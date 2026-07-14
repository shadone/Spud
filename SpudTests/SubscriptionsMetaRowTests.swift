//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import Testing
@testable import Spud

/// Drives `SubscriptionsViewModel.makeRow` (promoted from `private` to
/// internal so tests can call it directly) with real `CommunityRecord`
/// values, proving the view model actually wires `MetaCommunityClassifier`
/// into `SubscriptionsCommunityRow.isMeta` rather than merely asserting a
/// hand-constructed row's field exists.
@MainActor
struct SubscriptionsMetaRowTests {
    @Test
    func makeRow_metaCommunityName_flagsRowAsMeta() throws {
        let record = CommunityRecord(
            id: 1,
            accountId: 1,
            communityId: 1,
            name: "announcements",
            title: "Announcements",
            actorId: "https://lemmy.world/c/announcements"
        )

        let row = try #require(SubscriptionsViewModel.makeRow(from: record))
        #expect(row.isMeta)
    }

    @Test
    func makeRow_ordinaryCommunityName_doesNotFlagRowAsMeta() throws {
        let record = CommunityRecord(
            id: 2,
            accountId: 1,
            communityId: 2,
            name: "photography",
            title: "Photography",
            actorId: "https://lemmy.world/c/photography"
        )

        let row = try #require(SubscriptionsViewModel.makeRow(from: record))
        #expect(!row.isMeta)
    }
}
