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
