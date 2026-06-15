//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Adds a right-edge "forward" gesture to a navigation controller: swiping in
/// from the right edge re-pushes the most recently popped view controller (the
/// same instance), undoing an accidental Back. The system left-edge back gesture
/// is preserved unchanged.
///
/// A per-controller forward stack of popped view controllers is maintained by
/// `ForwardStackReducer`, fed from the navigation delegate's `didShow`. Attach via
/// `UINavigationController.enableForwardNavigationGesture()`, which retains the
/// driver for the controller's lifetime — UIKit holds delegates and gesture
/// targets weakly.
@MainActor
final class ForwardNavigationGestureDriver: NSObject {
    /// What the in-progress right-edge gesture is restoring.
    private enum GestureMode {
        /// An interactive push of a popped view controller from the forward stack.
        case navRestore
        /// A re-open of the most recently dismissed in-app browser (a modal
        /// present, so non-interactive — fires on release).
        case modalRestore
    }

    private weak var navigationController: UINavigationController?
    private var forwardStack: [UIViewController] = []
    private var lastStack: [UIViewController] = []
    private var interactionController: UIPercentDrivenInteractiveTransition?
    private var isInteracting = false
    private var mode: GestureMode?
    private let edgePan = UIScreenEdgePanGestureRecognizer()

    init(navigationController: UINavigationController) {
        self.navigationController = navigationController
        super.init()

        lastStack = navigationController.viewControllers

        edgePan.edges = .right
        edgePan.addTarget(self, action: #selector(handleEdgePan(_:)))
        edgePan.delegate = self
        navigationController.view.addGestureRecognizer(edgePan)

        // Taking the nav delegate can disable the system left-edge back gesture
        // unless we re-vend its shouldBegin, so we own both delegates.
        assert(navigationController.delegate == nil, "ForwardNavigationGestureDriver expects to be the navigation controller's sole delegate")
        navigationController.delegate = self
        navigationController.interactivePopGestureRecognizer?.delegate = self
    }

    @objc
    private func handleEdgePan(_ recognizer: UIScreenEdgePanGestureRecognizer) {
        guard let navigationController, let view = recognizer.view else { return }
        let translationX = recognizer.translation(in: view).x
        let progress = InteractiveTransitionGeometry.progress(translationX: translationX, viewWidth: view.bounds.width)

        switch recognizer.state {
        case .began:
            if let next = forwardStack.first {
                // Interactive push of a popped view controller. The forward stack
                // is mutated only by the reducer in didShow: a finished restore
                // nets an append-push (consumed), a cancelled one nets no change.
                mode = .navRestore
                isInteracting = true
                interactionController = UIPercentDrivenInteractiveTransition()
                navigationController.pushViewController(next, animated: true)
            } else if navigationController.pendingExternalLinkRestore != nil {
                // Nothing to push, but a dismissed in-app browser can be re-opened.
                // This is a modal present, so it is not interactive — it fires on
                // release if the swipe passed the threshold.
                mode = .modalRestore
                isInteracting = true
            }

        case .changed:
            guard isInteracting, mode == .navRestore else { return }
            interactionController?.update(progress)

        case .ended:
            guard isInteracting else { return }
            let velocityX = recognizer.velocity(in: view).x
            let finish = InteractiveTransitionGeometry.shouldFinish(progress: progress, velocityX: velocityX)
            switch mode {
            case .navRestore:
                if finish { interactionController?.finish() } else { interactionController?.cancel() }
            case .modalRestore:
                if finish {
                    let restore = navigationController.pendingExternalLinkRestore
                    navigationController.pendingExternalLinkRestore = nil
                    restore?()
                }
            case .none:
                break
            }
            endInteraction()

        case .cancelled, .failed:
            guard isInteracting else { return }
            if mode == .navRestore { interactionController?.cancel() }
            endInteraction()

        default:
            break
        }
    }

    private func endInteraction() {
        isInteracting = false
        interactionController = nil
        mode = nil
    }
}

extension ForwardNavigationGestureDriver: UINavigationControllerDelegate {
    func navigationController(_ navigationController: UINavigationController, didShow _: UIViewController, animated: Bool) {
        forwardStack = ForwardStackReducer.reduce(
            forwardStack: forwardStack,
            lastStack: lastStack,
            newStack: navigationController.viewControllers,
            animated: animated
        )
        lastStack = navigationController.viewControllers
        if animated {
            // A real navigation happened; any "re-open the dismissed link" intent
            // belonged to the previous context and is now stale.
            navigationController.pendingExternalLinkRestore = nil
        }
    }

    func navigationController(
        _: UINavigationController,
        animationControllerFor operation: UINavigationController.Operation,
        from _: UIViewController,
        to _: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        // Only take over while our right-edge interaction is live; back-button
        // taps, the left-edge gesture, programmatic pops, and normal pushes keep
        // the system default.
        (operation == .push && isInteracting) ? SlidePushAnimator() : nil
    }

    func navigationController(
        _: UINavigationController,
        interactionControllerFor _: UIViewControllerAnimatedTransitioning
    ) -> UIViewControllerInteractiveTransitioning? {
        interactionController
    }
}

extension ForwardNavigationGestureDriver: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let navigationController, navigationController.transitionCoordinator == nil else { return false }
        if gestureRecognizer === edgePan {
            // Our right-edge forward gesture: a popped controller to restore, or a
            // dismissed in-app browser to re-open.
            let canRestore = !forwardStack.isEmpty || navigationController.pendingExternalLinkRestore != nil
            return canRestore && !isInteracting
        }
        // The re-vended system left-edge back gesture: keep its default condition.
        return navigationController.viewControllers.count > 1
    }
}
