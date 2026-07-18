//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreGraphics

/// Pure accumulator turning a scroll view's contentOffset updates into user
/// scroll distance, UIKit-free so the logic is unit-testable (same approach
/// as `ScrollToTopUndo`).
///
/// Rules:
/// - Offsets are clamped to the scrollable range before diffing, so
///   rubber-band overshoot at either end contributes nothing.
/// - A single-event jump larger than one viewport height is treated as
///   programmatic (position restore, scroll-to-top) and only resyncs the
///   baseline.
/// - The first update after init/reset establishes the baseline.
struct ScrollOdometer {
    private var lastClampedY: CGFloat?
    private var accumulated: Double = 0

    mutating func update(offsetY: CGFloat, contentHeight: CGFloat, viewportHeight: CGFloat) {
        let maxOffset = max(0, contentHeight - viewportHeight)
        let clamped = min(max(offsetY, 0), maxOffset)
        defer { lastClampedY = clamped }
        guard let last = lastClampedY else { return }
        let delta = abs(clamped - last)
        guard delta > 0, delta <= viewportHeight else { return }
        accumulated += Double(delta)
    }

    /// Returns and clears the distance accumulated since the last take.
    mutating func take() -> Double {
        defer { accumulated = 0 }
        return accumulated
    }

    /// Re-credits points returned by `take()` that the caller chose not to
    /// report yet (sub-threshold batching).
    mutating func credit(_ points: Double) {
        accumulated += points
    }

    /// Forget the baseline (call when the content is replaced wholesale,
    /// e.g. a feed switch), so the next update cannot fabricate a delta.
    mutating func reset() {
        lastClampedY = nil
        accumulated = 0
    }
}
