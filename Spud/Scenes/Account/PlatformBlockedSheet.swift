//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import UIKit

extension UIViewController {
    /// Presents an action sheet explaining why the target instance can't be used
    /// here, offering to open it in Safari. Shared by the login and register
    /// flows so the copy and layout stay in one place.
    ///
    /// Two cases, distinguished by the software the error carries:
    /// - PieFed: Spud CAN sign in to PieFed (its Lemmy-compatible dialect), so
    ///   this sheet is only ever reached from the *register* flow — account
    ///   creation is web-only. The copy points the user to sign up on the web
    ///   and then come back to log in.
    /// - Any other non-Lemmy software: Spud can't connect at all (login or
    ///   register), so the copy says the software isn't supported.
    func presentPlatformBlockedSheet(_ blocked: PlatformUnsupportedError) {
        let title: String
        let message: String
        if blocked.software == .piefed {
            title = NSLocalizedString(
                "Sign up on the web",
                comment: "Block sheet title shown when creating a PieFed account, which is web-only"
            )
            message = String(
                format: NSLocalizedString(
                    "Spud can sign you in to %1$@, but creating a new %2$@ account has to be done on the web. Open %1$@ in Safari to sign up, then come back and log in.",
                    comment: "Block sheet body for PieFed registration; %1$@ is the host, %2$@ the software name"
                ),
                blocked.host, blocked.displayName
            )
        } else {
            title = String(
                format: NSLocalizedString(
                    "%@ isn't supported yet",
                    comment: "Block sheet title; %@ is a software name like Mastodon"
                ),
                blocked.displayName
            )
            message = String(
                format: NSLocalizedString(
                    "%1$@ runs %2$@. Spud can only connect to Lemmy instances right now.",
                    comment: "Block sheet body; %1$@ is the host, %2$@ the software name"
                ),
                blocked.host, blocked.displayName
            )
        }
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
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Block sheet: cancel button, dismisses the sheet"), style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        present(alert, animated: true)
    }
}
