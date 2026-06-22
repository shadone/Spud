//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Which placeholder, if any, the post-detail comments region shows behind the
/// always-present (opaque) post-header cell.
enum CommentsBackground: Equatable {
    /// A fetch is in flight, or the screen has just opened and no fetch has
    /// completed yet — and there are no comments on screen.
    case skeleton
    /// A comment fetch has completed and the post genuinely has no comments.
    case empty
    /// Comments are present; no background placeholder.
    case hidden

    /// Decides the comments-region background.
    ///
    /// The empty state is gated on `hasCompletedFetch` (not on "a snapshot has
    /// arrived"): a fresh open emits an empty *cached* snapshot before the
    /// network fetch starts, so gating on the snapshot would briefly flash the
    /// empty state before the skeleton. Defaulting to `.skeleton` until a fetch
    /// has actually completed avoids that flash.
    static func decide(
        isLoadingComments: Bool,
        hasCompletedFetch: Bool,
        hasComments: Bool
    ) -> CommentsBackground {
        if hasComments {
            return .hidden
        }
        if isLoadingComments {
            return .skeleton
        }
        if hasCompletedFetch {
            return .empty
        }
        return .skeleton
    }
}
