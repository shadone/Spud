//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

extension UINavigationController {
    private enum AssociatedKeys {
        nonisolated(unsafe) static var driver: UInt8 = 0
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
}
