//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SpudUIKit
import UIKit

extension UIViewController {
    /// Presents an action sheet explaining that `capability` isn't supported
    /// by the current instance's API version yet. Shared by every UI gating
    /// site (post/comment/community actions) so the copy and layout stay in
    /// one place. Fires the warning haptic like `presentSignInGate`; on iPad
    /// the sheet anchors to `sourceView` via a popover.
    func presentCapabilityGate(for capability: InstanceCapability, host: String?, sourceView: UIView?) {
        Haptics.warning()
        let copy = CapabilityGateCopy.copy(for: capability, host: host)
        let alert = UIAlertController(title: copy.title, message: copy.message, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("OK", comment: "Capability gate sheet: dismiss button"),
            style: .default
        ))
        if let popover = alert.popoverPresentationController {
            let anchor = sourceView ?? view
            popover.sourceView = anchor
            popover.sourceRect = CGRect(x: anchor?.bounds.midX ?? 0, y: anchor?.bounds.midY ?? 0, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        present(alert, animated: true)
    }
}
