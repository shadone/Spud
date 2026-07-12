//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Builds the feed cell's compact "Also in ..." text for a primary post's
/// collapsed cross-post siblings (see `CrossPostGrouper`). A single small,
/// unit-tested formatting decision shared by the cell's visible text and its
/// VoiceOver label, so the two never drift.
enum CrossPostAffordance {
    /// - Parameter communityNames: The collapsed siblings' community names, in
    ///   the same encounter order `CrossPostGrouper` collected them in. Empty
    ///   (no siblings) returns `nil` — the caller should hide the affordance
    ///   entirely rather than show empty text.
    ///
    /// Pluralization:
    /// - 1 sibling: "Also in c/\<community\>"
    /// - 2 siblings: "Also in c/\<a\>, c/\<b\>"
    /// - 3+ siblings: "Also in N communities" (the count, not the names — long
    ///   lists of names would overwhelm the feed's compact metadata line)
    static func summaryText(communityNames: [String]) -> String? {
        switch communityNames.count {
        case 0:
            return nil
        case 1:
            return String(
                format: NSLocalizedString(
                    "Also in c/%@",
                    comment: "Feed cell affordance: this post is also cross-posted to one other community; %@ is the community name"
                ),
                communityNames[0]
            )
        case 2:
            return String(
                format: NSLocalizedString(
                    "Also in c/%@, c/%@",
                    comment: "Feed cell affordance: this post is also cross-posted to two other communities; %@ are the community names"
                ),
                communityNames[0], communityNames[1]
            )
        default:
            return String(
                format: NSLocalizedString(
                    "Also in %d communities",
                    comment: "Feed cell affordance: this post is also cross-posted to three or more other communities; %d is the count"
                ),
                communityNames.count
            )
        }
    }
}
