//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Keyword sets that mark a community as "meta" (about the instance itself).
///
/// Centralized so the lists are tunable in one place. `strong` keywords are
/// unambiguous instance-meta signals (high confidence); `broad` keywords catch
/// more real meta communities at the cost of mislabeling some ordinary ones
/// (low confidence) — an accepted trade because meta status is only ever
/// *suggested*, never auto-acted on.
public enum MetaCommunityKeywords {
    public static let strong: Set<String> = [
        "meta", "announcements", "announcement", "changelog", "sitenews",
        "site", "instance",
    ]

    public static let broad: Set<String> = [
        "support", "help", "feedback", "news", "updates", "admin", "welcome",
        "general", "lounge", "rules", "moderators", "mods",
    ]
}
