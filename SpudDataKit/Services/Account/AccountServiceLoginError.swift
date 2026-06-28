//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

public enum AccountServiceLoginError: Error {
    /// The specified username/email or password was not accepted by the Lemmy server.
    case invalidLogin

    case totp2faRequired

    /// An unknown network error has occurred.
    case apiError(LemmyApiError)

    /// Internal error, this should not be happening.
    case missingJwt

    case internalInconsistency(description: String)

    init(from error: Error) {
        if let error = error as? LemmyApiError {
            if case let .serverError(errorResponse) = error {
                // Lemmy reports a TOTP-protected account two ways: it omits the
                // token entirely (2FA is enabled but no/empty code was sent) or
                // it sends the wrong code. Both mean "we need a valid 2FA code".
                if errorResponse.error == "missing_totp_token" || errorResponse.error == "incorrect_totp_token" {
                    self = .totp2faRequired
                } else if errorResponse.error == "incorrect_login" {
                    self = .invalidLogin
                } else {
                    self = .apiError(error)
                }
            } else {
                self = .apiError(error)
            }
        } else {
            assertionFailure("Unexpected exception \(type(of: error)): \(error))")
            self = .internalInconsistency(description: "Unexpected exception \(type(of: error)): \(error))")
        }
    }
}
