//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import UIKit

/// Presents the login screen in re-auth mode for an existing account: the
/// account's instance and username are pre-filled, the password is empty, and a
/// successful submit re-authenticates in place (no duplicate account). Every
/// session-expired hint surface routes here.
@MainActor
enum AccountReauthLauncher {
    static func present(
        forAccountKeychainId keychainId: String,
        from presenter: UIViewController,
        accountService: AccountServiceType,
        dependencies: LoginViewController.Dependencies
    ) {
        guard let instance = accountService.instanceActorId(forAccountKeychainId: keychainId) else {
            return
        }
        let row = SiteListRow.forTypedInstance(instance)
        let username = accountService.username(forAccountKeychainId: keychainId) ?? ""
        let loginViewController = LoginViewController(
            row: row,
            initialUsername: username,
            reauthTarget: .init(keychainId: keychainId),
            dependencies: dependencies
        )
        let navigationController = UINavigationController(rootViewController: loginViewController)
        presenter.present(navigationController, animated: true)
    }
}
