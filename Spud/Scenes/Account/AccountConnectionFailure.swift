//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudDataKit

/// Distinguishes a connection/transport failure (unreachable host, DNS
/// failure, timeout - the shape of failure a typo'd or offline custom
/// instance produces) from every other login/register failure (wrong
/// credentials, server rejection, unexpected error).
///
/// Login and register both wrap a failure that isn't already a specific auth
/// outcome in `LemmyApiError` (`AccountServiceLoginError.apiError` /
/// `AccountServiceRegisterError.apiError`). A transport failure surfaces there
/// as `LemmyApiError.network` - `LemmyApiError.init(from: ClientError)`
/// classifies any `NSURLErrorDomain` underlying error that way, as opposed to
/// the server actually responding with a rejection. Shared by `LoginViewModel`
/// and `RegisterViewModel` so a typo'd/unreachable custom instance address
/// isn't misreported as "Incorrect username or password."
enum AccountConnectionFailure {
    static func isConnectionFailure(_ error: Error) -> Bool {
        switch error {
        case let AccountServiceLoginError.apiError(apiError):
            isTransportFailure(apiError)
        case let AccountServiceRegisterError.apiError(apiError):
            isTransportFailure(apiError)
        default:
            false
        }
    }

    private static func isTransportFailure(_ apiError: LemmyApiError) -> Bool {
        if case .network = apiError {
            true
        } else {
            false
        }
    }

    /// "Couldn't connect to <host>. Check the address and your connection."
    static func message(host: String) -> String {
        String(
            format: NSLocalizedString(
                "Couldn't connect to %@. Check the address and your connection.",
                comment: "Login/Register: shown when the request to the instance fails at the transport level (DNS, timeout, no route) rather than the server rejecting the credentials, so a typo or offline instance isn't mislabeled as a wrong password."
            ),
            host
        )
    }
}
