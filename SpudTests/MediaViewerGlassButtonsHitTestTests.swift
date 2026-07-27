//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
import UIKit
@testable import Spud

/// Guards the media-viewer top-bar buttons (close / share / save), converted to
/// `.glass()` for Liquid Glass, against the documented tap-dead-zone bug class: a
/// button inside a superview with `isUserInteractionEnabled = false` renders fine
/// but can never receive a finger tap, because `hitTest` does not descend into a
/// disabled ancestor. Neither `sendActions(for:)` nor VoiceOver activation would
/// catch that, so this asserts real `hitTest` geometry instead — mirroring
/// `ImageBlockViewTests.failedPlateButtonsAreHitTestReachable`.
@MainActor
struct MediaViewerGlassButtonsHitTestTests {
    @Test
    func chromeButtonsAreHitTestReachable() throws {
        let url = try #require(URL(string: "https://example.test/media/photo.jpg"))
        let item = MediaItem(imageUrl: url)
        let vc = MediaViewerViewController(
            items: [item],
            startIndex: 0,
            dependencies: FakeDependencies()
        )
        vc.loadViewIfNeeded()
        vc.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        vc.view.layoutIfNeeded()

        for label in ["Close", "Share", "Save to Photos"] {
            let button = try #require(
                Self.button(accessibilityLabel: label, in: vc.view),
                "expected to find the \(label) button in the view hierarchy"
            )

            // The auto-hiding top bar starts hidden (alpha 0) until the user
            // taps; that is unrelated to the bug this test guards against, so
            // reveal every ancestor up to the root before hit-testing.
            Self.forceVisible(from: button, upTo: vc.view)
            vc.view.layoutIfNeeded()

            let center = vc.view.convert(
                CGPoint(x: button.bounds.midX, y: button.bounds.midY),
                from: button
            )
            let hit = vc.view.hitTest(center, with: nil)
            #expect(
                hit === button || hit?.isDescendant(of: button) == true,
                "a tap on \(label) must reach the button, not a disabled ancestor"
            )
        }
    }

    /// Guards against the other half of the same bug class, in the opposite
    /// direction: `chromeGlassContainerView` (added to host the top bar and
    /// caption pill under a shared `UIGlassContainerEffect`) is deliberately
    /// sized to the ENTIRE view, not just the two bars, so Apple's
    /// merge/morph geometry has room to compute proximity between them. A
    /// plain `UIVisualEffectView` used that way would hit-test as an opaque
    /// blocker everywhere neither bar is visible, because its own
    /// `contentView` is a normal, fully-interactive view spanning those same
    /// bounds — silently killing pinch-to-zoom, pan, tap-to-toggle-chrome,
    /// and paging on the photo underneath, none of which live inside this
    /// container. Neither `sendActions(for:)` nor VoiceOver activation would
    /// catch that either (both bypass hit-testing), so this asserts real
    /// `hitTest` geometry at a point over the photo, well clear of both bars.
    @Test
    func photoAreaIsNotSwallowedByGlassContainer() throws {
        let url = try #require(URL(string: "https://example.test/media/photo.jpg"))
        let item = MediaItem(imageUrl: url)
        let vc = MediaViewerViewController(
            items: [item],
            startIndex: 0,
            dependencies: FakeDependencies()
        )
        vc.loadViewIfNeeded()
        vc.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        vc.view.layoutIfNeeded()

        // Dead center of the view: well clear of the top bar (pinned near
        // the top) and the caption pill (pinned just above the page dots
        // near the bottom), so nothing but the container itself covers it.
        let midpoint = CGPoint(x: vc.view.bounds.midX, y: vc.view.bounds.midY)
        let hit = try #require(
            vc.view.hitTest(midpoint, with: nil),
            "expected a tap over the photo to hit something"
        )
        let zoomableImageView = try #require(
            Self.firstDescendant(ofType: ZoomableImageView.self, in: vc.view),
            "expected the current page to host a ZoomableImageView"
        )
        // Assert reachability positively (the hit IS the photo view or one
        // of its descendants), not just negatively (the hit "isn't" the
        // container) — `UIVisualEffectView.contentView` is UIKit's private
        // `_UIVisualEffectContentView`, which a same-type check against
        // `UIVisualEffectView` would silently miss, since the contentView
        // itself is a plain `UIView` subclass, not a `UIVisualEffectView`.
        #expect(
            hit === zoomableImageView || hit.isDescendant(of: zoomableImageView),
            "a tap over the photo must reach the zoomable image view underneath, not the glass chrome container"
        )
    }

    /// Recursively finds the first descendant of `root` whose type is `type`.
    private static func firstDescendant<T: UIView>(ofType type: T.Type, in root: UIView) -> T? {
        for subview in root.subviews {
            if let match = subview as? T {
                return match
            }
            if let found = firstDescendant(ofType: type, in: subview) {
                return found
            }
        }
        return nil
    }

    /// Recursively finds the first `UIButton` under `root` carrying
    /// `accessibilityLabel`.
    private static func button(accessibilityLabel: String, in root: UIView) -> UIButton? {
        for subview in root.subviews {
            if let button = subview as? UIButton, button.accessibilityLabel == accessibilityLabel {
                return button
            }
            if let found = button(accessibilityLabel: accessibilityLabel, in: subview) {
                return found
            }
        }
        return nil
    }

    /// Walks up from `view` to (and including) `root`, forcing every ancestor
    /// visible. Only touches `alpha`/`isHidden` (the auto-hide chrome's own
    /// animated state) — never `isUserInteractionEnabled`, which is exactly the
    /// property this test is checking was not left disabled.
    private static func forceVisible(from view: UIView, upTo root: UIView) {
        var current: UIView? = view
        while let node = current {
            node.alpha = 1
            node.isHidden = false
            if node === root { break }
            current = node.superview
        }
    }
}
