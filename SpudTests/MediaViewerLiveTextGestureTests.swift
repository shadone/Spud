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

    /// A viewer built WITH a `zoomSource`, so it is on the presentation path
    /// every production call site actually uses (`PostListViewController`,
    /// `PostDetailViewController`, `PersonViewController`, `ActivityViewController`,
    /// `CommunityViewController` all pass one). The tests above build the
    /// viewer with no `zoomSource` at all, so they only ever exercise the
    /// cross-dissolve fallback's `gestureRecognizerShouldBegin` — which is
    /// exactly how the zoom-transition path's equivalent gate shipped
    /// unreachable in production.
    private func makeZoomedViewController() -> MediaViewerViewController {
        let viewController = MediaViewerViewController(
            items: [MediaItem(imageUrl: URL(filePath: "/full.png"))],
            startIndex: 0,
            dependencies: MediaViewerTestDependencies(imageService: FakeImageService([.ready(solidImage())])),
            zoomSource: { _ in UIView() }
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

    // MARK: Zoom-transition path (Important 1 regression coverage)

    // The zoom-transition presentation's own `interactiveDismissShouldBegin`
    // closure is UIKit-invoked and not reachable from a test, so these tests
    // call `shouldBeginInteractiveDismiss(willBegin:at:)` directly — the
    // method the closure itself delegates to (see `MediaViewerViewController`
    // `init`). Exercising it on a viewer built WITH a `zoomSource`
    // (`makeZoomedViewController()`) is what makes this coverage meaningful:
    // without it, only the fallback pan's `gestureRecognizerShouldBegin` gate
    // above was ever tested, which is exactly why the zoom path's mirror of
    // it shipped dead in production (every real call site uses the zoom
    // path).

    /// Mirrors `dismissPanIsClaimedWithoutLiveTextUnderTheTouch`: with UIKit
    /// willing to begin, no zoom, and no Live Text under the touch, the
    /// interactive dismiss is allowed to begin.
    @Test
    func interactiveDismissIsClaimedWithoutLiveTextUnderTheTouch() {
        let viewController = makeZoomedViewController()

        #expect(viewController.shouldBeginInteractiveDismiss(willBegin: true, at: CGPoint(x: 100, y: 100)))
    }

    /// When UIKit's own `willBegin` is already false (e.g. an upward or
    /// horizontal flick), the closure's return value must not override it into
    /// a dismiss.
    @Test
    func interactiveDismissIsNotClaimedWhenUIKitWouldNotBeginIt() {
        let viewController = makeZoomedViewController()

        #expect(!viewController.shouldBeginInteractiveDismiss(willBegin: false, at: CGPoint(x: 100, y: 100)))
    }

    /// Mirrors `dismissPanIsRefusedWhileTextIsSelected`: this is the exact case
    /// Important 1 covers — with text selected, the zoom transition's own
    /// interactive dismiss must yield to VisionKit, not just the fallback pan.
    @Test
    func interactiveDismissIsRefusedWhileTextIsSelected() {
        let viewController = makeZoomedViewController()
        viewController.liveTextSelectionActiveOverrideForTesting = true

        #expect(!viewController.shouldBeginInteractiveDismiss(willBegin: true, at: CGPoint(x: 100, y: 100)))
    }

    /// Mirrors `dismissPanIsRefusedOnAnInteractiveItem`: a drag starting on
    /// live text or the Live Text button belongs to VisionKit on the zoom path
    /// too.
    @Test
    func interactiveDismissIsRefusedOnAnInteractiveItem() {
        let viewController = makeZoomedViewController()
        viewController.liveTextInteractiveItemOverrideForTesting = true

        #expect(!viewController.shouldBeginInteractiveDismiss(willBegin: true, at: CGPoint(x: 100, y: 100)))
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
