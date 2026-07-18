//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// The device-wide "fun stats" odometer counters. Raw values are the `key`
/// column of the `funStat` table — renaming a case orphans its history, so
/// treat raw values as frozen once shipped.
public enum FunStatKey: String, CaseIterable, Sendable {
    // Motion and touch
    case scrollDistancePoints
    case tapCount
    case pullToRefreshCount

    // Reading
    case postsOpened
    case postsSeen
    case imagesViewed
    case linksOpened

    // Time
    case sessionCount
    case foregroundSeconds

    // Engagement
    case votesCast
    case commentsPosted
    case postsPosted
    case searchesRun
}
