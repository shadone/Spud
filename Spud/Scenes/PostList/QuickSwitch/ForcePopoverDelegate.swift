//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Keeps an attached presentation a popover even in a compact (iPhone) size
/// class, instead of letting it adapt to a full-screen sheet. Retain an
/// instance for the lifetime of the presenting controller and assign it as the
/// popover presentation controller's delegate.
final class ForcePopoverDelegate: NSObject, UIPopoverPresentationControllerDelegate {
    func adaptivePresentationStyle(
        for controller: UIPresentationController,
        traitCollection: UITraitCollection
    ) -> UIModalPresentationStyle {
        .none
    }
}
