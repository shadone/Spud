//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SwiftUI
import UIKit

/// The signed-out (anonymous) state of the Account tab. Hosts the SwiftUI
/// `AccountSignedOutView` in a `UIHostingController` so the grouped layout matches
/// the redesigned signed-in Account tab and the account switcher.
///
/// Navigation is owned by the parent `AccountViewController`, reached through the
/// callbacks forwarded here:
/// - `onChangeInstance` presents the account switcher (its "Browse an instance
///   anonymously" path changes the home server),
/// - `onCreateAccount` / `onLogIn` both open the add-account flow (instance picker
///   -> sign up / log in),
/// - `onSettings` pushes Preferences.
final class AccountSignedOutViewController: UIHostingController<AccountSignedOutView> {
    /// Creates the signed-out screen for `instanceHostname` (the anonymous
    /// account's home host, shown in the "Reading from" row), wiring each control
    /// to the parent controller's navigation callbacks.
    init(
        instanceHostname: String,
        accent: Color,
        onChangeInstance: @escaping () -> Void,
        onCreateAccount: @escaping () -> Void,
        onLogIn: @escaping () -> Void,
        onSettings: @escaping () -> Void
    ) {
        super.init(rootView: AccountSignedOutView(
            instanceHostname: instanceHostname,
            accent: accent,
            onChangeInstance: onChangeInstance,
            onCreateAccount: onCreateAccount,
            onLogIn: onLogIn,
            onSettings: onSettings
        ))
    }

    @available(*, unavailable)
    @MainActor
    dynamic required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
