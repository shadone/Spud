//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudDataKit

struct StarterPackCatalogTests {
    private func row(_ url: String, name: String, members: Int64) -> CommunityListRow {
        CommunityListRow(
            id: Int64(abs(url.hashValue % 1_000_000)),
            communityUrl: url,
            instanceHost: "lemmy.world",
            name: name,
            numberOfSubscribers: members
        )
    }

    @Test
    func resolve_attachesMatchedCommunitiesInCuratedOrder() {
        let pack = StarterPack(
            id: "p",
            title: "Pack",
            blurb: "b",
            communityUrls: [
                "https://lemmy.world/c/technology",
                "https://lemmy.world/c/missing",
                "https://lemmy.world/c/linux",
            ]
        )
        let rows = [
            row("https://lemmy.world/c/linux", name: "linux", members: 100),
            row("https://lemmy.world/c/technology", name: "technology", members: 300),
        ]

        let resolved = StarterPackCatalog.resolve([pack], using: rows)
        #expect(resolved.count == 1)
        // Curated order is preserved, and the missing URL is skipped.
        #expect(resolved[0].communities.map(\.name) == ["technology", "linux"])
        #expect(resolved[0].communityCount == 2)
        #expect(resolved[0].totalSubscribers == 400)
    }

    @Test
    func resolve_dropsPacksWithNoMatches() {
        let pack = StarterPack(id: "p", title: "Pack", blurb: "b", communityUrls: ["https://nope.test/c/x"])
        #expect(StarterPackCatalog.resolve([pack], using: []).isEmpty)
    }

    @Test
    func catalog_isNonEmptyAndUniqueIds() {
        let ids = StarterPackCatalog.all.map(\.id)
        #expect(!(ids.isEmpty))
        #expect(ids.count == Set(ids).count, "pack ids are unique")
    }
}
