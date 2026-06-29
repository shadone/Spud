//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

extension Preferences {
    /// How many posts an offline download saves. Offered as a small set of
    /// generous presets in the "Download for offline" chooser; the chosen value
    /// caps both the feed-page fetch and the per-post content phase in
    /// `OfflineDownloadService`.
    ///
    /// Backed by its raw `Int` count so the stored preference is the literal post
    /// count (forward-compatible — a new preset is just a new case). The default
    /// is ``oneHundred`` (100), the conservative, polite amount.
    enum OfflineDownloadPostCount: Int, RawRepresentable, Codable, CaseIterable, Identifiable {
        case oneHundred = 100
        case twoHundredFifty = 250
        case fiveHundred = 500

        /// The preset selected when the user has never chosen, and the floor the
        /// chooser opens on.
        static let `default` = OfflineDownloadPostCount.oneHundred

        /// The literal post count this preset represents — passed straight to
        /// `OfflineDownloadService.download(...)` as its `maxPosts`.
        var count: Int {
            rawValue
        }

        var id: Int {
            rawValue
        }

        /// The picker row label, e.g. "100 posts".
        var title: String {
            let format = NSLocalizedString(
                "%d posts",
                comment: "Offline-download post-count picker row, e.g. '100 posts'; %d is the count"
            )
            return String(format: format, count)
        }
    }
}
