//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import Testing
import UIKit
@testable import Spud

/// Verifies the media viewer yields its own gestures to Live Text: the
/// chrome-toggling tap and the swipe-to-dismiss drag must not fire on top of
/// selectable text, a data detector, or the Live Text button.
@MainActor
struct MediaViewerLiveTextGestureTests {
    private func solidImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
    }

    private func makeViewController() -> MediaViewerViewController {
        let viewController = MediaViewerViewController(
            items: [MediaItem(imageUrl: URL(filePath: "/full.png"))],
            startIndex: 0,
            dependencies: MediaViewerTestDependencies(imageService: FakeImageService([.ready(solidImage())]))
        )
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.view.layoutIfNeeded()
        return viewController
    }

    /// The dismiss pan is a downward, mostly-vertical drag on an un-zoomed
    /// image. Without live text under the touch it is still claimed.
    @Test
    func dismissPanIsClaimedWithoutLiveTextUnderTheTouch() {
        let viewController = makeViewController()
        let pan = StubPanGestureRecognizer(velocity: CGPoint(x: 0, y: 800))

        #expect(viewController.gestureRecognizerShouldBegin(pan))
    }

    /// An upward drag is never the dismiss gesture, live text or not.
    @Test
    func upwardPanIsNotClaimed() {
        let viewController = makeViewController()
        let pan = StubPanGestureRecognizer(velocity: CGPoint(x: 0, y: -800))

        #expect(!viewController.gestureRecognizerShouldBegin(pan))
    }

    /// With text selected, a downward drag belongs to the selection, not to
    /// swipe-to-dismiss.
    @Test
    func dismissPanIsRefusedWhileTextIsSelected() {
        let viewController = makeViewController()
        viewController.liveTextSelectionActiveOverrideForTesting = true
        let pan = StubPanGestureRecognizer(velocity: CGPoint(x: 0, y: 800))

        #expect(!viewController.gestureRecognizerShouldBegin(pan))
    }

    /// A drag starting on live text or on the Live Text button belongs to
    /// VisionKit.
    @Test
    func dismissPanIsRefusedOnAnInteractiveItem() {
        let viewController = makeViewController()
        viewController.liveTextInteractiveItemOverrideForTesting = true
        let pan = StubPanGestureRecognizer(velocity: CGPoint(x: 0, y: 800))

        #expect(!viewController.gestureRecognizerShouldBegin(pan))
    }
}

/// A pan recognizer with a canned velocity, so a gesture-arbitration test does
/// not need a real touch sequence.
private final class StubPanGestureRecognizer: UIPanGestureRecognizer {
    private let stubbedVelocity: CGPoint

    init(velocity: CGPoint) {
        stubbedVelocity = velocity
        super.init(target: nil, action: nil)
    }

    override func velocity(in _: UIView?) -> CGPoint {
        stubbedVelocity
    }

    override func location(in _: UIView?) -> CGPoint {
        CGPoint(x: 100, y: 100)
    }
}
