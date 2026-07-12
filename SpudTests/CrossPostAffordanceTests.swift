//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import Spud

/// Covers the pluralization of the feed cell's "Also in ..." cross-post
/// affordance text.
struct CrossPostAffordanceTests {
    @Test
    func noSiblingsReturnsNil() {
        #expect(CrossPostAffordance.summaryText(communityNames: []) == nil)
    }

    @Test
    func oneSiblingNamesTheCommunity() {
        #expect(CrossPostAffordance.summaryText(communityNames: ["news"]) == "Also in c/news")
    }

    @Test
    func twoSiblingsNameBothCommunities() {
        #expect(
            CrossPostAffordance.summaryText(communityNames: ["news", "worldnews"])
                == "Also in c/news, c/worldnews"
        )
    }

    @Test
    func threeSiblingsCollapseToACount() {
        #expect(
            CrossPostAffordance.summaryText(communityNames: ["a", "b", "c"])
                == "Also in 3 communities"
        )
    }

    @Test
    func manySiblingsCollapseToACount() {
        #expect(
            CrossPostAffordance.summaryText(communityNames: ["a", "b", "c", "d", "e"])
                == "Also in 5 communities"
        )
    }
}
