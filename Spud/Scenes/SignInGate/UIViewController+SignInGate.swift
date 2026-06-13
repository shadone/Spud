//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudUIKit
import UIKit

extension UIViewController {
    /// Presents the designed sign-in gate with an already-localized `title`
    /// (e.g. "Sign in to vote") a signed-out user triggered. Fires the warning
    /// haptic, and if the user chooses to authenticate, routes to the Account
    /// tab (which offers log-in and sign-up). Replaces the ad-hoc "you need to
    /// be signed in" alerts.
    func presentSignInGate(title: String) {
        Haptics.warning()
        let gate = SignInGateViewController(title: title) { [weak self] in
            (self?.view.window as? MainWindow)?.selectAccountTab()
        }
        present(gate, animated: true)
    }
}
