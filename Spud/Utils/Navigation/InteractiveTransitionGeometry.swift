//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreGraphics

/// Pure geometry / decision helpers for the right-edge interactive forward gesture.
///
/// Deliberately free of UIKit object state so the gesture's behaviour can be unit
/// tested without a live navigation transition.
enum InteractiveTransitionGeometry {
    /// Fraction of the screen width past which lifting the finger completes the
    /// transition instead of cancelling it.
    static let completionThreshold: CGFloat = 0.5

    /// Horizontal speed (points/second) treated as a deliberate fling.
    static let flingVelocity: CGFloat = 800

    /// Maps pan translation to progress in `0...1`. The right-edge gesture drags
    /// leftwards, so a negative `translationX` increases progress.
    static func progress(translationX: CGFloat, viewWidth: CGFloat) -> CGFloat {
        guard viewWidth > 0 else { return 0 }
        let fraction = -translationX / viewWidth
        return min(max(fraction, 0), 1)
    }

    /// Whether to finish (complete the transition) or cancel (snap back) when the
    /// finger lifts. A clear fling wins over position; otherwise the halfway point
    /// decides.
    static func shouldFinish(progress: CGFloat, velocityX: CGFloat) -> Bool {
        if velocityX < -flingVelocity { return true } // flung left -> finish
        if velocityX > flingVelocity { return false } // flung right -> cancel
        return progress > completionThreshold
    }
}
