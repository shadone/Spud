//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Animates a navigation push driven by the right-edge forward swipe: the
/// incoming (restored) view slides in from the right following the finger, while
/// the outgoing view slides left with a slight parallax and a dim overlay that
/// fades in. Mirrors the system push so it reads as "going forward".
///
/// Honours `isReduceMotionEnabled` by collapsing to an instant cut.
final class SlidePushAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private let parallax: CGFloat = 0.3
    private let dimMaxAlpha: CGFloat = 0.15

    func transitionDuration(using _: UIViewControllerContextTransitioning?) -> TimeInterval {
        UIAccessibility.isReduceMotionEnabled ? 0 : 0.3
    }

    func animateTransition(using context: UIViewControllerContextTransitioning) {
        let container = context.containerView

        guard
            let toViewController = context.viewController(forKey: .to),
            let fromView = context.view(forKey: .from),
            let toView = context.view(forKey: .to)
        else {
            context.completeTransition(false)
            return
        }

        let width = container.bounds.width
        let toFinalFrame = context.finalFrame(for: toViewController)

        // Incoming (restored) view starts off to the right, on top.
        toView.frame = toFinalFrame.offsetBy(dx: width, dy: 0)
        container.addSubview(toView)

        // Dim overlay over the outgoing view, fading in as it recedes.
        let dimView = UIView(frame: fromView.bounds)
        dimView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dimView.backgroundColor = .black
        dimView.alpha = 0
        fromView.addSubview(dimView)

        let fromStartFrame = fromView.frame
        let fromEndFrame = fromStartFrame.offsetBy(dx: -width * parallax, dy: 0)
        let dimMax = dimMaxAlpha

        UIView.animate(
            withDuration: transitionDuration(using: context),
            delay: 0,
            options: .curveEaseOut,
            animations: {
                toView.frame = toFinalFrame
                fromView.frame = fromEndFrame
                dimView.alpha = dimMax
            },
            completion: { _ in
                dimView.removeFromSuperview()
                if context.transitionWasCancelled {
                    // Restore the outgoing view to its start frame; the incoming
                    // view is fully removed (not frame-restored) because we added
                    // it — do not "restore" toView here or a stale view would linger.
                    fromView.frame = fromStartFrame
                    toView.removeFromSuperview()
                    context.completeTransition(false)
                } else {
                    context.completeTransition(true)
                }
            }
        )
    }
}
