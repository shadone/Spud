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
}
