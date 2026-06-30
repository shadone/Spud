//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import UIKit

/// Centralizes the Activity screen's empty / offline / sparse state copy and the
/// `UIContentUnavailableConfiguration` builder, so the view controller and the
/// snapshot tests render the exact same content (no copy drift between them).
/// Button actions for the general-empty escape hatches are attached by the
/// caller; this only builds the presentation.
enum ActivityStateContent {
    // MARK: General empty ("Your story starts here")

    static let generalEmptyTitle = NSLocalizedString(
        "Your story starts here",
        comment: "Activity general empty title"
    )
    static let generalEmptyMessage = NSLocalizedString(
        "Vote, comment, save, and read posts — what you do shows up here.",
        comment: "Activity general empty message"
    )
    static let browseCommunitiesTitle = NSLocalizedString(
        "Browse communities",
        comment: "Activity empty: browse communities button"
    )
    static let seeSavedTitle = NSLocalizedString(
        "See saved",
        comment: "Activity empty: see saved button"
    )

    // MARK: Voted first run / sparse (forward-only, no version number)

    static let votedTitle = NSLocalizedString(
        "Votes start filling in now",
        comment: "Activity voted first-run / sparse title"
    )
    static let votedFirstRunMessage = NSLocalizedString(
        "Spud records the posts and comments you vote on from here on. Earlier votes aren't shown.",
        comment: "Activity voted first-run message (forward-only, no version number)"
    )

    // MARK: Generic filtered empty

    static let filteredEmptyTitle = NSLocalizedString(
        "Nothing here yet",
        comment: "Activity filtered empty title"
    )
    static let filteredEmptyMessage = NSLocalizedString(
        "Activity matching this filter will show up here.",
        comment: "Activity filtered empty message"
    )

    // MARK: Offline banner

    static let offlineBannerText = NSLocalizedString(
        "You're offline — showing what's on this device",
        comment: "Activity offline banner"
    )
    static let offlineRetryTitle = NSLocalizedString(
        "Retry",
        comment: "Activity offline banner retry button"
    )

    /// The full-screen empty state for the active filters: general
    /// ("Your story starts here" with two escape-hatch buttons), the honest
    /// voted first-run, or a generic per-filter empty. The caller attaches
    /// `buttonProperties.primaryAction` / `secondaryButtonProperties.primaryAction`
    /// for the general case.
    static func emptyConfiguration(filters: Set<ActivityFilterType>) -> UIContentUnavailableConfiguration {
        var config = UIContentUnavailableConfiguration.empty()
        if filters.isEmpty {
            config.image = UIImage(systemName: "sparkles")
            config.text = generalEmptyTitle
            config.secondaryText = generalEmptyMessage
            var browse = UIButton.Configuration.borderedProminent()
            browse.title = browseCommunitiesTitle
            config.button = browse
            var saved = UIButton.Configuration.plain()
            saved.title = seeSavedTitle
            config.secondaryButton = saved
        } else if filters == [.vote] {
            config.image = UIImage(systemName: "arrow.up.arrow.down")
            config.text = votedTitle
            config.secondaryText = votedFirstRunMessage
        } else {
            config.image = UIImage(systemName: "tray")
            config.text = filteredEmptyTitle
            config.secondaryText = filteredEmptyMessage
        }
        return config
    }
}
