//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// How a feed load failure should be surfaced, given whether the feed currently
/// has posts on screen.
///
/// This is deliberately a pure, view-agnostic decision (a sibling to
/// `FeedStatePresenter`) so the invariant is named and unit-testable rather than
/// buried in the view controller: **a feed that already has content must never be
/// replaced by the full inline error surface.** That surface is a transparent
/// `UIContentUnavailableConfiguration`, so laying it over live posts renders the
/// error copy see-through on top of them (a shipped visual bug). Whenever posts
/// are displayed, the failure is surfaced as a transient toast and the posts stay
/// — matching the documented rule "the feed does not drop into an error state when
/// it already has content" (`docs/features/feed-loading.md`).
enum FeedFailurePresentation: Equatable {
    /// Keep the existing posts on screen and surface the failure as a toast.
    case keepContentWithToast
    /// Replace the (empty) list with the full inline error surface. Safe because
    /// there are no posts behind the transparent overlay.
    case fullErrorSurface

    /// Decides how to surface a feed load failure.
    ///
    /// - Parameter hasContent: whether the feed currently displays any posts.
    ///   This is the *only* signal that matters. A previous implementation also
    ///   gated on `UIRefreshControl.isRefreshing`, but that flag is not a reliable
    ///   proxy for "posts on screen": a non-pull reload, a reconnect retry, or a
    ///   racing `endRefreshing()` can clear it while posts remain — which let the
    ///   full error surface overlap the feed.
    static func decide(hasContent: Bool) -> FeedFailurePresentation {
        hasContent ? .keepContentWithToast : .fullErrorSurface
    }
}
