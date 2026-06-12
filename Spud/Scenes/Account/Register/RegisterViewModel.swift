//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Observation
import OSLog
import SpudDataKit

private let logger = Logger.app

/// Drives the Sign Up screen. The instance is already chosen upstream (the
/// site-list / login flow), so this only collects the new account's details and
/// calls `AccountService.register`. Surfaces the pending / verify-email states
/// the server may return on success.
///
/// Captcha is not collected here: the no-captcha path is implemented fully and
/// instances that require a captcha surface a server-side rejection the UI
/// reports. Captcha entry is a follow-up (see RELEASE-PLAN feel pass).
@MainActor
@Observable
final class RegisterViewModel {
    let row: SiteListRow
    let instanceName: String

    var username: String = ""
    var email: String = ""
    var password: String = ""
    var passwordVerify: String = ""
    var showNsfw: Bool = false
    /// Required application answer for instances with "require application"
    /// enabled. Optional otherwise.
    var applicationAnswer: String = ""

    /// True while a register request is in flight.
    var isSubmitting: Bool = false

    /// Set when registration succeeded and the account is immediately usable -
    /// the view dismisses back to the app.
    var loggedIn: Bool = false

    /// A non-fatal outcome to surface to the user: a pending / verify-email
    /// state, or a rejection message. Drives an alert.
    var outcomeMessage: String?

    var submitEnabled: Bool {
        !username.isEmpty &&
            !password.isEmpty &&
            password == passwordVerify &&
            !isSubmitting
    }

    @ObservationIgnored
    private let accountService: AccountServiceType

    init(
        row: SiteListRow,
        accountService: AccountServiceType
    ) {
        self.row = row
        self.accountService = accountService
        instanceName = row.hostname
    }

    func register() async {
        guard submitEnabled else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAnswer = applicationAnswer.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let result = try await accountService.register(
                atInstance: row.instance,
                username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                email: trimmedEmail.isEmpty ? nil : trimmedEmail,
                password: password,
                passwordVerify: passwordVerify,
                showNsfw: showNsfw,
                captchaUuid: nil,
                captchaAnswer: nil,
                answer: trimmedAnswer.isEmpty ? nil : trimmedAnswer
            )

            switch result {
            case .loggedIn:
                loggedIn = true
            case .applicationPending:
                outcomeMessage = NSLocalizedString(
                    "Your account was created and is awaiting approval by the instance admins. You'll be able to log in once it's approved.",
                    comment: "Register: application-pending message"
                )
            case .verifyEmail:
                outcomeMessage = NSLocalizedString(
                    "Your account was created. Check your email and verify your address, then log in.",
                    comment: "Register: verify-email message"
                )
            case .pending:
                outcomeMessage = NSLocalizedString(
                    "Your account was created but isn't active yet. Try logging in shortly.",
                    comment: "Register: generic-pending message"
                )
            }
        } catch let error as AccountServiceRegisterError {
            outcomeMessage = Self.message(for: error)
        } catch {
            logger.error("Register failed: \(String(describing: error), privacy: .public)")
            outcomeMessage = NSLocalizedString(
                "Sign up failed. Please try again.",
                comment: "Register: generic failure message"
            )
        }
    }

    private static func message(for error: AccountServiceRegisterError) -> String {
        switch error {
        case let .rejected(message):
            if let message, !message.isEmpty {
                return String(
                    format: NSLocalizedString(
                        "Sign up was rejected: %@",
                        comment: "Register: server rejection message, includes the server's reason"
                    ),
                    message.replacingOccurrences(of: "_", with: " ")
                )
            }
            return NSLocalizedString(
                "Sign up was rejected by the instance. The username may be taken, the password too weak, or a captcha may be required.",
                comment: "Register: generic rejection message"
            )
        case .apiError, .internalInconsistency:
            return NSLocalizedString(
                "Sign up failed. Please check your connection and try again.",
                comment: "Register: api-error message"
            )
        }
    }
}
