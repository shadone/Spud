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

/// Drives the Create-account screen. The instance is already chosen upstream (the
/// site-list / login flow), so this only collects the new account's details and
/// calls `AccountService.register`. Surfaces the pending / verify-email states
/// the server may return on success.
///
/// Application requirement: `SiteListRow` does not carry the instance's
/// registration mode, so the view model cannot know up-front whether an
/// application answer is required. `requiresApplication` defaults to `false`
/// (no note box, no answer field, the CTA reads "Create account"); when an
/// upstream flow knows the instance requires an application it can flip the
/// flag to surface the note, the answer field, and the "Submit application" CTA.
/// In either case the server is the source of truth: an `.applicationPending`
/// outcome routes to the Pending-review screen regardless of this flag.
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

    /// Whether this instance requires an application answer. Drives the note
    /// box, the answer field, and the CTA label ("Submit application" vs
    /// "Create account"). See the type doc for why this isn't derived from the
    /// site row.
    var requiresApplication: Bool = false

    /// True while a register request is in flight.
    var isSubmitting: Bool = false

    /// Set when registration succeeded and the account is immediately usable -
    /// the view dismisses back to the app.
    var loggedIn: Bool = false

    /// A successful-but-not-logged-in outcome routed to the Pending-review
    /// screen (application awaiting approval, or email verification needed).
    /// Distinct from `outcomeMessage`, which drives an alert for rejections /
    /// failures.
    var pendingOutcome: PendingOutcome?

    /// A non-fatal outcome to surface to the user in an alert: a server
    /// rejection or a generic failure message.
    var outcomeMessage: String?

    /// The successful-but-pending states routed to `PendingReviewViewController`.
    enum PendingOutcome: Equatable {
        /// The account is awaiting admin approval (instance requires an
        /// application). Email may still need confirming.
        case applicationPending
        /// The account was created but an email must be verified before login.
        case verifyEmail
        /// Pending for an unspecified reason.
        case pending
    }

    /// The primary CTA's title: "Submit application" when the instance requires
    /// an application answer, else "Create account".
    var submitButtonTitle: String {
        requiresApplication
            ? NSLocalizedString("Submit application", comment: "Create-account CTA when an application is required")
            : NSLocalizedString("Create account", comment: "Create-account CTA when no application is required")
    }

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
                pendingOutcome = .applicationPending
            case .verifyEmail:
                pendingOutcome = .verifyEmail
            case .pending:
                pendingOutcome = .pending
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

    #if DEBUG
    /// Test-only: forces the application-required variant so snapshot references
    /// can render the note box, answer field, and "Submit application" CTA
    /// without depending on live site metadata (which the row doesn't carry).
    /// Mirrors `LoginTwoFactorViewController.setCodeForTesting`.
    func setRequiresApplicationForTesting(_ requires: Bool) {
        requiresApplication = requires
    }
    #endif
}
