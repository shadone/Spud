//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

extension UINavigationController {
    private enum AssociatedKeys {
        nonisolated(unsafe) static var driver: UInt8 = 0
        nonisolated(unsafe) static var pendingExternalLinkRestore: UInt8 = 0
    }

    private final class ClosureBox {
        let action: () -> Void
        init(_ action: @escaping () -> Void) {
            self.action = action
        }
    }

    /// Adds a right-edge "forward" gesture that re-pushes the most recently popped
    /// view controller, alongside the unchanged system left-edge back gesture.
    /// Idempotent; retains its driver for this controller's life.
    @MainActor
    func enableForwardNavigationGesture() {
        guard objc_getAssociatedObject(self, &AssociatedKeys.driver) == nil else { return }
        let driver = ForwardNavigationGestureDriver(navigationController: self)
        objc_setAssociatedObject(self, &AssociatedKeys.driver, driver, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    /// A pending action that re-opens the most recently shown in-app browser
    /// (SFSafariViewController), set by `AppService` when it presents one.
    ///
    /// The right-edge forward gesture invokes this when there is no popped view
    /// controller to restore, giving an "undo the dismiss" for external links — a
    /// fresh load of the same URL, since SFSafariViewController cannot be reused.
    /// Cleared on the next navigation transition.
    @MainActor
    var pendingExternalLinkRestore: (() -> Void)? {
        get { (objc_getAssociatedObject(self, &AssociatedKeys.pendingExternalLinkRestore) as? ClosureBox)?.action }
        set {
            let box = newValue.map { ClosureBox($0) }
            objc_setAssociatedObject(self, &AssociatedKeys.pendingExternalLinkRestore, box, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}
