//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Presents a view controller as a drawer pinned to the leading edge: a
/// fixed-width panel over a dimmed, tap-to-dismiss backdrop. Used by the
/// quick-switch drawer so it matches the muscle memory of the old
/// swipe-the-list-in-from-the-left gesture.
final class LeadingDrawerPresentationController: UIPresentationController {
    /// Drawer width as a fraction of the container, capped so it doesn't get
    /// silly-wide on iPad / landscape.
    private let widthRatio: CGFloat = 0.82
    private let maxWidth: CGFloat = 420

    private lazy var dimmingView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        view.alpha = 0
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dimmingTapped)))
        return view
    }()

    @objc
    private func dimmingTapped() {
        presentingViewController.dismiss(animated: true)
    }

    override var frameOfPresentedViewInContainerView: CGRect {
        guard let containerView else { return .zero }
        let width = min(containerView.bounds.width * widthRatio, maxWidth)
        return CGRect(x: 0, y: 0, width: width, height: containerView.bounds.height)
    }

    override func presentationTransitionWillBegin() {
        guard let containerView else { return }
        dimmingView.frame = containerView.bounds
        dimmingView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        containerView.insertSubview(dimmingView, at: 0)

        presentedView?.layer.cornerRadius = 0
        presentedViewController.transitionCoordinator?.animate { _ in
            self.dimmingView.alpha = 1
        }
    }

    override func dismissalTransitionWillBegin() {
        presentedViewController.transitionCoordinator?.animate { _ in
            self.dimmingView.alpha = 0
        }
    }

    override func containerViewDidLayoutSubviews() {
        presentedView?.frame = frameOfPresentedViewInContainerView
    }
}

/// Slides the drawer in from / out to the leading edge.
final class LeadingDrawerAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private let isPresenting: Bool

    init(isPresenting: Bool) {
        self.isPresenting = isPresenting
    }

    func transitionDuration(using _: UIViewControllerContextTransitioning?) -> TimeInterval {
        isPresenting ? 0.32 : 0.26
    }

    func animateTransition(using context: UIViewControllerContextTransitioning) {
        let container = context.containerView

        if isPresenting {
            guard
                let toViewController = context.viewController(forKey: .to),
                let toView = context.view(forKey: .to)
            else {
                context.completeTransition(false)
                return
            }
            let finalFrame = context.finalFrame(for: toViewController)
            toView.frame = finalFrame.offsetBy(dx: -finalFrame.width, dy: 0)
            container.addSubview(toView)

            UIView.animate(
                withDuration: transitionDuration(using: context),
                delay: 0,
                usingSpringWithDamping: 0.92,
                initialSpringVelocity: 0,
                options: .curveEaseOut
            ) {
                toView.frame = finalFrame
            } completion: { _ in
                context.completeTransition(!context.transitionWasCancelled)
            }
        } else {
            guard let fromView = context.view(forKey: .from) else {
                context.completeTransition(false)
                return
            }
            UIView.animate(
                withDuration: transitionDuration(using: context),
                delay: 0,
                options: .curveEaseIn
            ) {
                fromView.frame = fromView.frame.offsetBy(dx: -fromView.frame.width, dy: 0)
            } completion: { _ in
                context.completeTransition(!context.transitionWasCancelled)
            }
        }
    }
}

/// Wires a presented controller up to the leading-edge drawer presentation.
/// The presenter must keep a strong reference (UIKit holds the delegate weakly).
final class LeadingDrawerTransitioningDelegate: NSObject, UIViewControllerTransitioningDelegate {
    func presentationController(
        forPresented presented: UIViewController,
        presenting: UIViewController?,
        source _: UIViewController
    ) -> UIPresentationController? {
        LeadingDrawerPresentationController(presentedViewController: presented, presenting: presenting)
    }

    func animationController(
        forPresented _: UIViewController,
        presenting _: UIViewController,
        source _: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        LeadingDrawerAnimator(isPresenting: true)
    }

    func animationController(
        forDismissed _: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        LeadingDrawerAnimator(isPresenting: false)
    }
}
