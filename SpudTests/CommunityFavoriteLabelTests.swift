//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
@testable import Spud

/// Pins the shared "Add to Favorites" / "Remove from Favorites" copy +
/// symbols rendered by every surface (community overflow menu, community
/// context-menu builder). If this helper's wording or symbol choice ever
/// drifts, every surface drifts together - that's the point of centralizing
/// it here rather than hardcoding the strings at each call site.
struct CommunityFavoriteLabelTests {
    @Test
    func title_notFavorited_isAddToFavorites() {
        #expect(CommunityFavoriteLabel.title(isFavorited: false) == "Add to Favorites")
    }

    @Test
    func title_favorited_isRemoveFromFavorites() {
        #expect(CommunityFavoriteLabel.title(isFavorited: true) == "Remove from Favorites")
    }

    @Test
    func symbol_notFavorited_isStar() {
        #expect(CommunityFavoriteLabel.symbol(isFavorited: false) == "star")
    }

    @Test
    func symbol_favorited_isStarSlash() {
        #expect(CommunityFavoriteLabel.symbol(isFavorited: true) == "star.slash")
    }

    /// The on/off symbols must differ - the whole point of a state-driven
    /// action is that it's visually distinguishable per state.
    @Test
    func symbol_differsByState() {
        #expect(CommunityFavoriteLabel.symbol(isFavorited: true) != CommunityFavoriteLabel.symbol(isFavorited: false))
    }

    /// The two titles must differ - a shared string would leave the user
    /// unable to tell from the menu alone whether tapping favorites or
    /// unfavorites.
    @Test
    func titles_differByState() {
        #expect(CommunityFavoriteLabel.title(isFavorited: true) != CommunityFavoriteLabel.title(isFavorited: false))
    }
}
