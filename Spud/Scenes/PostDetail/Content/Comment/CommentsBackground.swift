//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit

/// Which placeholder, if any, the post-detail comments region shows. The
/// `.skeleton` (fetch in flight), `.empty` ("No comments yet"), and
/// `.failed` (the comment fetch errored with no comments to show) states render
/// as in-flow rows in the comments section — right after the header, so they
/// scroll with content and land where the comments will appear, instead of being
/// centered behind the pinned header the way a table background view would be.
/// `.hidden` shows no placeholder.
enum CommentsBackground: Equatable {
    /// A fetch is in flight, or the screen has just opened and no fetch has
    /// completed yet — and there are no comments on screen.
    case skeleton
    /// A comment fetch has completed and the post genuinely has no comments.
    case empty
    /// The most recent comment fetch failed and there are no comments to show.
    /// Carries the classified failure so the row can render a truthful
    /// offline / unreachable message instead of the misleading "No comments
    /// yet" empty state, with a Retry affordance.
    case failed(LoadFailure)
    /// Comments are present; no background placeholder.
    case hidden

    /// Decides the comments-region background.
    ///
    /// Precedence, when no comments are loaded: a fetch failure (`fetchError`)
    /// wins over the empty state — a failed initial load must never read as "no
    /// comments yet". The skeleton wins while a fetch is in flight. The empty
    /// state is otherwise gated on `hasCompletedFetch` (not on "a snapshot has
    /// arrived"): a fresh open emits an empty *cached* snapshot before the
    /// network fetch starts, so gating on the snapshot would briefly flash the
    /// empty state before the skeleton. Defaulting to `.skeleton` until a fetch
    /// has actually completed avoids that flash.
    ///
    /// - Parameter fetchError: The classified failure of the most recent comment
    ///   fetch, or nil when the last fetch succeeded (or none has run). A failure
    ///   here only surfaces when there are no comments to show; once any comments
    ///   are loaded the list stays on screen and a refresh failure is surfaced as
    ///   a toast by the view controller instead.
    static func decide(
        isLoadingComments: Bool,
        hasCompletedFetch: Bool,
        hasComments: Bool,
        fetchError: LoadFailure? = nil
    ) -> CommentsBackground {
        if hasComments {
            return .hidden
        }
        if isLoadingComments {
            return .skeleton
        }
        // A failed fetch (with no comments to show) takes precedence over the
        // empty state: showing "No comments yet" after an offline failure is
        // the misleading state this exists to fix.
        if let fetchError {
            return .failed(fetchError)
        }
        if hasCompletedFetch {
            return .empty
        }
        return .skeleton
    }
}
