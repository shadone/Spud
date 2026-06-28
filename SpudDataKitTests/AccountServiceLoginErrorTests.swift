//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import Testing
@testable import SpudDataKit

/// `AccountServiceLoginError.init(from:)` maps Lemmy's server errors to the
/// typed login error the UI keys off. The two-factor cases are the focus: Lemmy
/// reports a TOTP-protected account either by complaining the token is missing
/// (`missing_totp_token`, 2FA enabled but no/empty code) or wrong
/// (`incorrect_totp_token`); both map to `.totp2faRequired` so the login flow can
/// prompt for a code.
struct AccountServiceLoginErrorTests {
    private func mapped(serverError error: String) -> AccountServiceLoginError {
        let errorResponse = Components.Schemas.ErrorResponse(error: error, message: nil)
        return AccountServiceLoginError(from: LemmyApiError.serverError(errorResponse))
    }

    @Test
    func missingTotpTokenMapsToTotp2faRequired() {
        guard case .totp2faRequired = mapped(serverError: "missing_totp_token") else {
            Issue.record("expected .totp2faRequired for missing_totp_token")
            return
        }
    }

    @Test
    func incorrectTotpTokenMapsToTotp2faRequired() {
        guard case .totp2faRequired = mapped(serverError: "incorrect_totp_token") else {
            Issue.record("expected .totp2faRequired for incorrect_totp_token")
            return
        }
    }

    @Test
    func incorrectLoginMapsToInvalidLogin() {
        guard case .invalidLogin = mapped(serverError: "incorrect_login") else {
            Issue.record("expected .invalidLogin for incorrect_login")
            return
        }
    }

    @Test
    func genericServerErrorMapsToApiError() {
        guard case .apiError = mapped(serverError: "couldnt_find_that_username_or_email") else {
            Issue.record("expected .apiError for a generic server error")
            return
        }
    }
}
