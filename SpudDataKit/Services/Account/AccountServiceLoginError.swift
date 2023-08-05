//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

public enum AccountServiceLoginError: Error {
    /// The specified username or email was not accepted by the Lemmy server.
    case invalidUsernameOrEmail

    /// The specified password was not accepted by the Lemmy server.
    case invalidPassword

    case totp2faRequired

    /// An unknown network error has occurred.
    case apiError(LemmyApiError)

    /// Internal error, this should not be happening.
    case missingJwt
}
