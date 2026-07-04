//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// A `UIWindow` whose `safeAreaInsets` are pinned to `.zero`, so a snapshot
/// rendered through `drawHierarchyInKeyWindow: true` is independent of the
/// ambient window-scene state.
///
/// swift-snapshot-testing's key-window render path reuses whichever `UIWindow`
/// is currently key (`getKeyWindow()`) and lays the view hierarchy out under
/// *that window's* safe area. A stock `UIWindow` derives its safe area from its
/// scene attachment, which an earlier snapshot suite in the same test process
/// can perturb — shifting the whole capture vertically, so a recorded reference
/// only matches the process state it was recorded in. Overriding `safeAreaInsets`
/// removes that dependency; `.zero` matches the zero-safe-area the strategy
/// already forces via its off-screen draw, so first-layout and draw-layout agree
/// and the render is byte-identical whatever ran before it. This mirrors the
/// private `Window` subclass swift-snapshot-testing uses for its own
/// non-key-window render path.
///
/// Shared by every snapshot suite that hosts a view controller on a real key
/// window and captures with `drawHierarchyInKeyWindow: true`
/// (`ActivityIPadSplitSnapshotTests`, `SummarySnapshotTests`).
final class FixedSafeAreaWindow: UIWindow {
    override var safeAreaInsets: UIEdgeInsets {
        .zero
    }
}

/// Determinism helpers shared by the snapshot suites that host a view controller
/// on a real key window and capture with `drawHierarchyInKeyWindow: true`.
///
/// A live on-screen capture is exposed to three sources of frame-to-frame
/// nondeterminism that an off-screen `layer.render(in:)` capture is not:
/// in-flight `UIView` animations, layer-level *implicit* animations that ignore
/// `UIView.areAnimationsEnabled` (e.g. a `UISegmentedControl`'s selection
/// indicator), and stray scroll offsets from a mid-load layout pass. These
/// helpers neutralize all three so the pixel capture reflects the settled final
/// state regardless of timing.
@MainActor
enum SnapshotDeterminism {
    /// Disables `UIView` animations and returns a closure that restores the
    /// previous state. Snapshot tests must render the settled *final* state, not
    /// a transient animation frame; disabling animations makes state changes
    /// applied during fixture assembly (chip / segment selection) take effect
    /// instantly rather than fading.
    ///
    /// Call at the start of a capture and invoke the returned closure (typically
    /// via `defer`) once the capture is done.
    static func disableAnimationsForCapture() -> () -> Void {
        let previous = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        return { UIView.setAnimationsEnabled(previous) }
    }

    /// Recursively removes every CoreAnimation animation from a view's whole
    /// layer tree (including layers not backed by a `UIView`, such as a
    /// `UISegmentedControl`'s selection indicator), snapping each layer to its
    /// final model value so the pixel capture is timing-independent.
    ///
    /// Needed on top of ``disableAnimationsForCapture()``: some UIKit controls
    /// kick off `CATransaction`-level implicit animations that ignore
    /// `UIView.areAnimationsEnabled`.
    static func snapAllAnimations(in view: UIView) {
        snapAllAnimations(inLayer: view.layer)
        for subview in view.subviews {
            snapAllAnimations(in: subview)
        }
    }

    private static func snapAllAnimations(inLayer layer: CALayer) {
        layer.removeAllAnimations()
        for sublayer in layer.sublayers ?? [] {
            snapAllAnimations(inLayer: sublayer)
        }
    }

    /// Resets every `UIScrollView` in the subtree to its natural top offset
    /// (`-adjustedContentInset.top`). Content that starts scrolled to the top
    /// makes this a no-op; it exists so a stray content offset (e.g. from a
    /// mid-load layout pass) can never make the pixel capture non-deterministic.
    static func pinScrollViewsToTop(in view: UIView) {
        if let scrollView = view as? UIScrollView {
            scrollView.contentOffset = CGPoint(x: 0, y: -scrollView.adjustedContentInset.top)
        }
        for subview in view.subviews {
            pinScrollViewsToTop(in: subview)
        }
    }
}
