//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudDataKit
import Testing
@testable import Spud

/// `AccountConnectionFailure` distinguishes a transport/reachability failure
/// (the shape of failure a typo'd or offline custom instance produces) from
/// every other login/register failure, so `LoginViewModel` and
/// `RegisterViewModel` can show "Couldn't connect to <host>" instead of
/// implying the entered credentials were wrong.
struct AccountConnectionFailureTests {
    // MARK: Login errors

    @Test
    func loginNetworkFailure_isConnectionFailure() {
        let error = AccountServiceLoginError.apiError(.network(URLError(.cannotFindHost)))
        #expect(AccountConnectionFailure.isConnectionFailure(error))
    }

    @Test
    func loginInvalidLogin_isNotConnectionFailure() {
        #expect(!AccountConnectionFailure.isConnectionFailure(AccountServiceLoginError.invalidLogin))
    }

    @Test
    func loginTotp2faRequired_isNotConnectionFailure() {
        #expect(!AccountConnectionFailure.isConnectionFailure(AccountServiceLoginError.totp2faRequired))
    }

    @Test
    func loginNonNetworkApiError_isNotConnectionFailure() {
        let errorResponse = Lemmy.ErrorResponse(error: "some_other_error", message: nil)
        let error = AccountServiceLoginError.apiError(.serverError(errorResponse))
        #expect(!AccountConnectionFailure.isConnectionFailure(error))
    }

    // MARK: Register errors

    @Test
    func registerNetworkFailure_isConnectionFailure() {
        let error = AccountServiceRegisterError.apiError(.network(URLError(.timedOut)))
        #expect(AccountConnectionFailure.isConnectionFailure(error))
    }

    @Test
    func registerRejected_isNotConnectionFailure() {
        let error = AccountServiceRegisterError.rejected(message: "registration_closed")
        #expect(!AccountConnectionFailure.isConnectionFailure(error))
    }

    // MARK: Unrelated errors

    @Test
    func unrelatedError_isNotConnectionFailure() {
        struct SomeOtherError: Error { }
        #expect(!AccountConnectionFailure.isConnectionFailure(SomeOtherError()))
    }

    // MARK: message(host:)

    @Test
    func message_includesHost() {
        let message = AccountConnectionFailure.message(host: "lemmy.example.com")
        #expect(message.contains("lemmy.example.com"))
    }
}
