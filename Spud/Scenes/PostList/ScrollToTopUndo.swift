//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreGraphics

/// Pure state machine for the post list's "undo accidental scroll-to-top".
///
/// A status-bar tap scrolls the feed to the top. When that happens from deep in
/// the feed it is usually accidental, so we offer a one-tap undo that snaps back
/// to the prior position. The capability lives here, independent of any toast,
/// so a second status-bar tap (a toggle) still undoes even after the hint toast
/// has expired - until the user manually scrolls or the feed changes.
///
/// UIKit-free (operates on `CGPoint` / `Int64` only) so the decision logic is
/// unit-testable without a view controller.
struct ScrollToTopUndo {
    /// A captured place to return to: the exact content offset plus the server
    /// post id of the row to pulse on restore.
    struct Pending: Equatable {
        var offset: CGPoint
        var anchorServerPostId: Int64
    }

    /// What the view controller should do in response to a status-bar tap.
    enum TapResponse: Equatable {
        /// No undo armed: record a candidate and let iOS scroll to the top
        /// (return `true` from `scrollViewShouldScrollToTop`).
        case allowScrollToTop
        /// An undo is armed and we are at the top: consume the tap (return
        /// `false`) and perform the undo instead.
        case undo
    }

    /// The armed undo, surviving until the user moves on. `nil` when nothing is
    /// armed. Readable by the view controller to gate toast dismissal.
    private(set) var pending: Pending?

    /// The pre-jump position recorded between `statusBarTapped` and
    /// `scrolledToTop`, promoted to `pending` only if the jump was deep enough.
    private var candidate: Pending?

    /// Intercepts a status-bar tap (from `scrollViewShouldScrollToTop`).
    /// Returns `.undo` when an undo is already armed (toggle back); otherwise
    /// records the current position as a candidate and returns `.allowScrollToTop`.
    mutating func statusBarTapped(
        currentOffset: CGPoint,
        topVisibleServerPostId: Int64?
    ) -> TapResponse {
        if pending != nil {
            return .undo
        }
        candidate = topVisibleServerPostId.map {
            Pending(offset: currentOffset, anchorServerPostId: $0)
        }
        return .allowScrollToTop
    }

    /// Called from `scrollViewDidScrollToTop` after iOS finished scrolling.
    /// Promotes the candidate to an armed undo when the pre-jump offset was at
    /// least `viewportHeight` deep (about one screen). Returns the armed
    /// `Pending` (show the undo toast) or `nil` (stay silent).
    mutating func scrolledToTop(viewportHeight: CGFloat) -> Pending? {
        defer { candidate = nil }
        guard let candidate, candidate.offset.y >= viewportHeight else {
            return nil
        }
        pending = candidate
        return candidate
    }

    /// Consumes the armed undo (toast button or toggle re-tap). Returns the
    /// `Pending` to restore, or `nil` if nothing is armed.
    mutating func takeUndo() -> Pending? {
        defer { pending = nil }
        return pending
    }

    /// Drops any armed/candidate undo - the user manually scrolled or the feed
    /// changed, so the saved position is stale.
    mutating func invalidate() {
        pending = nil
        candidate = nil
    }
}
