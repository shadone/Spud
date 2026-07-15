//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit

/// Recognizes the specific "this account's stored session is no longer valid"
/// rejection, so the passive site refresh and the mutation outbox can flag the
/// account for re-login. This is a NARROW check layered on top of
/// `OutboxFailureClass` (which correctly treats all of these as `.permanent`
/// for rollback) -- it answers only "is this an expired/revoked session", NOT
/// "should this roll back".
///
/// Deliberately EXCLUDES a bare HTTP 403 (`unknownServerError(403)`): that is a
/// WAF/CDN block, not an auth failure, and must never trigger a re-login hint.
public enum AuthExpiry {
    /// Lemmy error codes that mean "you are not authenticated" on a write. Lemmy
    /// returns this (HTTP 400) when a stored JWT is expired/revoked.
    private static let authCodes: Set<String> = ["not_logged_in"]

    /// `true` when `error` is a genuine auth-expiry, unwrapping both the bare
    /// `LemmyApiError` and the `LemmyServiceError.apiError` wrapper.
    public static func isAuthExpiry(_ error: Error) -> Bool {
        switch error {
        case let apiError as LemmyApiError:
            return isAuthExpiry(apiError)
        case let .apiError(apiError) as LemmyServiceError:
            return isAuthExpiry(apiError)
        default:
            return false
        }
    }

    private static func isAuthExpiry(_ apiError: LemmyApiError) -> Bool {
        switch apiError {
        case .unauthorized:
            // HTTP 401 with Lemmy's UnauthorizedResponse.
            return true
        case let .serverError(errorResponse):
            // HTTP 400 carrying a Lemmy error body, e.g. not_logged_in.
            return authCodes.contains(errorResponse.error)
        case let .unknownServerError(httpStatusCode, _):
            // v4 GET /account rejects an invalid token with 401. A bare 403 is
            // WAF/CDN, NOT auth -- excluded here on purpose.
            return httpStatusCode == 401
        case .network, .failedToDeserializeResponse, .unknown, .unsupportedByDialect:
            return false
        }
    }
}
