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

    /// The deepest pre-jump position armed since the last undo or feed change,
    /// preserved across manual scrolls (unlike `pending`, which a scroll
    /// disarms). Scrolling partway back down toward where you were is part of
    /// recovering, so a following scroll-to-top keeps returning to this original
    /// deep position rather than the shallower spot you stopped at.
    private var deepestUnconsumed: Pending?

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
    /// Arms an undo to the deepest position worth returning to: this jump's
    /// pre-jump offset when it was at least `viewportHeight` deep (about one
    /// screen), or a deeper position remembered from an earlier jump in the same
    /// recovery sequence (so re-jumping after scrolling partway back still
    /// returns to the original deep spot). Returns the armed `Pending` (show the
    /// undo toast) or `nil` (stay silent).
    mutating func scrolledToTop(viewportHeight: CGFloat) -> Pending? {
        defer { candidate = nil }
        let deepCandidate = candidate.flatMap { $0.offset.y >= viewportHeight ? $0 : nil }
        let target = [deepCandidate, deepestUnconsumed]
            .compactMap { $0 }
            .max { $0.offset.y < $1.offset.y }
        guard let target else { return nil }
        pending = target
        deepestUnconsumed = target
        return target
    }

    /// Consumes the armed undo (toast button or toggle re-tap). Returns the
    /// `Pending` to restore, or `nil` if nothing is armed. Ends the recovery
    /// sequence, so the deepest-position memory is cleared too.
    mutating func takeUndo() -> Pending? {
        defer {
            pending = nil
            deepestUnconsumed = nil
        }
        return pending
    }

    /// The user manually scrolled. Disarm the toggle (and let the caller drop the
    /// hint toast), but keep the deepest un-consumed return target - scrolling
    /// back down toward where you were is part of recovering, not a fresh start.
    mutating func userDidScroll() {
        pending = nil
        candidate = nil
    }

    /// Hard reset - the feed changed, so the saved position belongs to a feed
    /// that is no longer on screen. Drops everything, including the deep memory.
    mutating func invalidate() {
        pending = nil
        candidate = nil
        deepestUnconsumed = nil
    }
}
