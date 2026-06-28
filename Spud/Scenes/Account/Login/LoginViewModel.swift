//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Observation
import SpudDataKit
import UIKit

@MainActor
@Observable
final class LoginViewModel {
    typealias OwnDependencies =
        HasAccountService &
        HasAlertService &
        HasImageService
    typealias NestedDependencies =
        HasVoid
    typealias Dependencies = NestedDependencies & OwnDependencies

    @ObservationIgnored
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    private var accountService: AccountServiceType {
        dependencies.own.accountService
    }

    private var alertService: AlertServiceType {
        dependencies.own.alertService
    }

    private var imageService: ImageServiceType {
        dependencies.own.imageService
    }

    let row: SiteListRow
    let instanceName: String

    var icon: UIImage
    var username: String = "" {
        didSet { loginError = nil }
    }

    var password: String = "" {
        didSet { loginError = nil }
    }

    /// Two-factor (TOTP) one-time code collected by `LoginTwoFactorViewController`.
    /// Captured here so the login flow owns it and forwarded to
    /// `accountService.login(...)`. When the server reports that 2FA is required
    /// (`AccountServiceLoginError.totp2faRequired`), `login()` flips
    /// `needsTwoFactorCode` so the view controller can prompt for the code; once
    /// the user enters one and retries, the forwarded token lets the login succeed.
    var totp2faToken: String?

    var loggedIn: Bool = false

    /// One-shot signal raised when the server reports a 2FA-protected account and
    /// no valid code was supplied yet. The view controller observes this to
    /// auto-present the two-factor code-entry screen. It is reset to `false`
    /// before each login attempt so the next required-2FA response re-fires it.
    var needsTwoFactorCode: Bool = false

    /// User-facing error surfaced inline under the password field after a failed
    /// login attempt. The existing alert (via `AlertService`) still fires too;
    /// this is an additive view-layer affordance. `nil` means no error.
    var loginError: String?

    var loginButtonEnabled: Bool {
        !username.isEmpty && !password.isEmpty
    }

    @ObservationIgnored
    private var iconFetchTask: Task<Void, Never>?

    init(
        row: SiteListRow,
        dependencies: Dependencies
    ) {
        self.row = row
        self.dependencies = (own: dependencies, nested: dependencies)
        instanceName = row.hostname

        let placeholder = UIImage(systemName: "questionmark")!
        icon = placeholder

        if let iconUrl = row.iconUrl {
            let stream = dependencies.imageService.fetch(iconUrl)
            iconFetchTask = Task { [weak self] in
                for await state in stream {
                    guard let self else { return }
                    switch state {
                    case .loading:
                        break
                    case let .ready(loaded):
                        icon = loaded
                    case .failure:
                        icon = placeholder
                    }
                }
            }
        }
    }

    deinit {
        iconFetchTask?.cancel()
    }

    func login() async {
        loginError = nil
        needsTwoFactorCode = false
        do {
            try await accountService.login(
                atInstance: row.instance,
                username: username,
                password: password,
                totp2faToken: totp2faToken
            )
            loggedIn = true
        } catch AccountServiceLoginError.totp2faRequired {
            // The account has two-factor enabled and no valid code was supplied
            // yet. Surface an inline hint and ask the view layer to prompt for the
            // code; don't route this through the generic error alert.
            loginError = NSLocalizedString(
                "Enter your two-factor code.",
                comment: "Inline hint shown when a 2FA code is required to log in"
            )
            needsTwoFactorCode = true
        } catch {
            loginError = NSLocalizedString(
                "Incorrect username or password.",
                comment: "Inline login error shown under the password field"
            )
            alertService.handle(error, for: .login)
        }
    }
}
