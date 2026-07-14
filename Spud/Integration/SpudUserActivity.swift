// Spud/Integration/SpudUserActivity.swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreSpotlight
import Foundation

/// Builds and decodes the `NSUserActivity` objects Spud vends from content
/// screens. Every activity carries the canonical routing URL
/// (`info.ddenis.spud://internal/...`) in `userInfo["url"]`, so continuation and
/// Spotlight taps funnel through the same `AppCoordinator.open` path as deep
/// links. Pure value logic (no database / UIKit dependency) so it is
/// unit-testable in isolation.
enum SpudUserActivity {
    static let viewPostType = "info.ddenis.Spud.viewPost"
    static let viewCommunityType = "info.ddenis.Spud.viewCommunity"
    static let viewPersonType = "info.ddenis.Spud.viewPerson"

    /// `userInfo` key holding the routing URL string.
    static let routingURLKey = "url"

    /// Our own activity types (also declared in `Info.plist`'s `NSUserActivityTypes`).
    static let allTypes = [viewPostType, viewCommunityType, viewPersonType]

    /// Builds the Handoff/Spotlight/Siri activity for a viewed post.
    ///
    /// Returns `nil` for an NSFW post (post OR its community flagged NSFW):
    /// NSFW posts must never be advertised to Handoff, Spotlight, or Siri
    /// suggestions, unconditionally — independent of the user's "Show NSFW"
    /// preference, which only controls in-app visibility.
    static func viewPost(routingURL: URL, title: String, isNsfw: Bool) -> NSUserActivity? {
        guard !isNsfw else { return nil }
        return make(type: viewPostType, routingURL: routingURL, title: title)
    }

    static func viewCommunity(routingURL: URL, name: String) -> NSUserActivity {
        make(type: viewCommunityType, routingURL: routingURL, title: "!\(name)")
    }

    static func viewPerson(routingURL: URL, handle: String) -> NSUserActivity {
        make(type: viewPersonType, routingURL: routingURL, title: handle)
    }

    private static func make(type: String, routingURL: URL, title: String) -> NSUserActivity {
        let activity = NSUserActivity(activityType: type)
        activity.title = title
        activity.userInfo = [routingURLKey: routingURL.absoluteString]
        activity.keywords = Set(title.split(separator: " ").map(String.init))
        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch = true
        activity.isEligibleForPrediction = true
        activity.persistentIdentifier = routingURL.absoluteString
        return activity
    }

    /// Decodes the routing URL from a continued activity: either one of our own
    /// activities (URL in `userInfo`) or a Spotlight item tap
    /// (`CSSearchableItemActionType`, identifier in
    /// `CSSearchableItemActivityIdentifier`).
    static func routingURL(from activity: NSUserActivity) -> URL? {
        if activity.activityType == CSSearchableItemActionType,
           let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String
        {
            return URL(string: identifier)
        }
        if allTypes.contains(activity.activityType),
           let urlString = activity.userInfo?[routingURLKey] as? String
        {
            return URL(string: urlString)
        }
        return nil
    }
}
