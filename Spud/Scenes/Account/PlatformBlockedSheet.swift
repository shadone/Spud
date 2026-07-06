//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import UIKit

extension UIViewController {
    /// Presents an action sheet explaining that the target instance runs
    /// non-Lemmy software, offering to open it in Safari. Shared by the login
    /// and register flows so the copy and layout stay in one place.
    func presentPlatformBlockedSheet(_ blocked: PlatformUnsupportedError) {
        let title = String(
            format: NSLocalizedString(
                "%@ isn't supported yet",
                comment: "Block sheet title; %@ is a software name like PieFed"
            ),
            blocked.displayName
        )
        let message = String(
            format: NSLocalizedString(
                "%1$@ runs %2$@. Spud can only connect to Lemmy instances right now.",
                comment: "Block sheet body; %1$@ is the host, %2$@ the software name"
            ),
            blocked.host, blocked.displayName
        )
        let alert = UIAlertController(title: title, message: message, preferredStyle: .actionSheet)
        if let url = URL(string: "https://\(blocked.host)") {
            alert.addAction(UIAlertAction(
                title: NSLocalizedString(
                    "Open in Safari",
                    comment: "Block sheet: open the instance in the browser"
                ),
                style: .default
            ) { _ in UIApplication.shared.open(url) })
        }
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        present(alert, animated: true)
    }
}
