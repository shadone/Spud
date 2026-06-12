//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

/// The outcome of a successful (HTTP 200) registration request. Lemmy's
/// `register` endpoint returns either a usable JWT or a description of a
/// pending state - the account exists but cannot log in yet because the
/// instance requires admin approval and/or email verification first.
public enum AccountServiceRegisterResult: Equatable, Sendable {
    /// Registration completed and the account is immediately usable. The
    /// credential has been stored and the account marked default, mirroring
    /// `login`.
    case loggedIn

    /// The account was created but is awaiting admin approval (the instance
    /// has "require application" enabled). No credential is stored.
    case applicationPending

    /// The account was created but an email must be verified before logging
    /// in (the instance has email verification enabled). No credential is
    /// stored.
    case verifyEmail

    /// The account was created but is pending for an unspecified reason (no
    /// JWT was returned and neither pending flag was set). No credential is
    /// stored.
    case pending

    /// Maps a Lemmy `LoginResponse` to a result. When a JWT is present this is
    /// `.loggedIn` (the caller stores the credential); otherwise the pending
    /// flags select the user-facing state.
    init(response: Components.Schemas.LoginResponse) {
        if response.jwt != nil {
            self = .loggedIn
        } else if response.verify_email_sent {
            self = .verifyEmail
        } else if response.registration_created {
            self = .applicationPending
        } else {
            self = .pending
        }
    }
}

public enum AccountServiceRegisterError: Error {
    /// The instance rejected the registration (e.g. username taken, weak
    /// password, captcha required/incorrect). Carries the server message.
    case rejected(message: String?)

    /// An unknown network or API error occurred.
    case apiError(LemmyApiError)

    /// Internal error; should not happen.
    case internalInconsistency(description: String)

    init(from error: Error) {
        if let error = error as? LemmyApiError {
            switch error {
            case let .serverError(errorResponse):
                self = .rejected(message: errorResponse.error)
            case let .unauthorized(message):
                self = .rejected(message: message)
            default:
                self = .apiError(error)
            }
        } else {
            self = .internalInconsistency(description: "Unexpected exception \(type(of: error)): \(error)")
        }
    }
}
