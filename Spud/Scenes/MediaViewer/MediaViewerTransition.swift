//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// A simple cross-dissolve present/dismiss animator for the media viewer.
///
/// Cross-dissolve is the low-risk choice called for in the design brief: it
/// reads as a smooth fade-up to full screen without the fragility of a
/// matched-geometry zoom transition. Honours `isReduceMotionEnabled` by
/// collapsing to an instant cut.
final class MediaViewerTransition: NSObject, UIViewControllerAnimatedTransitioning {
    enum Direction {
        case present
        case dismiss
    }

    private let direction: Direction

    init(direction: Direction) {
        self.direction = direction
        super.init()
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        UIAccessibility.isReduceMotionEnabled ? 0 : 0.3
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        let containerView = transitionContext.containerView
        let duration = transitionDuration(using: transitionContext)

        switch direction {
        case .present:
            guard let toView = transitionContext.view(forKey: .to) else {
                transitionContext.completeTransition(false)
                return
            }
            toView.frame = transitionContext.finalFrame(
                for: transitionContext.viewController(forKey: .to)!
            )
            toView.alpha = 0
            containerView.addSubview(toView)

            UIView.animate(
                withDuration: duration,
                delay: 0,
                options: .curveEaseOut,
                animations: { toView.alpha = 1 },
                completion: { _ in
                    transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
                }
            )

        case .dismiss:
            guard let fromView = transitionContext.view(forKey: .from) else {
                transitionContext.completeTransition(false)
                return
            }
            UIView.animate(
                withDuration: duration,
                delay: 0,
                options: .curveEaseIn,
                animations: { fromView.alpha = 0 },
                completion: { _ in
                    transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
                }
            )
        }
    }
}
