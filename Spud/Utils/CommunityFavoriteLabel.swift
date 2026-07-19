//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Centralized copy + symbols for the community Favourite action, shared by
/// the community screen's overflow menu and the community context-menu
/// builder so the wording can't drift.
enum CommunityFavoriteLabel {
    /// The menu action's title, which flips between the favorite/unfavorite
    /// phrasing (unlike `CommunityNotifyLabel.title`, which stays fixed and
    /// conveys state via a checkmark instead).
    static func title(isFavorited: Bool) -> String {
        isFavorited
            ? NSLocalizedString("Remove from Favorites", comment: "Overflow action to unfavorite a community")
            : NSLocalizedString("Add to Favorites", comment: "Overflow action to favorite a community")
    }

    /// The SF Symbol name for the action, reflecting the current state.
    static func symbol(isFavorited: Bool) -> String {
        isFavorited ? "star.slash" : "star"
    }
}
