//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// The fixed fire rule for a community "new posts" follow. Deliberately NOT
/// the activity rule's 5-or-24h shape: meta/announcement communities post
/// rarely, so >= 1 new post fires (batched - one notification per check
/// regardless of count). Zero new posts never fires.
public enum CommunityFollowRule {
    /// When the new-post count equals the fetched page size and reaches this
    /// threshold, the notification body reads "N+ new posts" - there may be
    /// more beyond the single fetched page.
    public static let saturationThreshold = 10

    /// Same throttle as activity follows; forwards `ReminderActivityRule`'s
    /// constant so every write site stays in agreement.
    public static let pollInterval: TimeInterval = ReminderActivityRule.pollInterval

    public static func shouldFire(newPosts: Int) -> Bool {
        newPosts >= 1
    }
}
