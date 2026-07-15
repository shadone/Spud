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
    /// Error codes that mean "you are not authenticated" on a write/read using a
    /// stored session, across dialects. Matched as a PREFIX of
    /// `ErrorResponse.error`, not an exact string:
    ///
    /// - Lemmy's `not_logged_in` (HTTP 400) is always exact.
    /// - PieFed's `incorrect_login` (also HTTP 400, surfaced through LemmyKit's
    ///   `PiefedClient` error mapping) is NOT code-stable across routes --
    ///   confirmed LIVE against `piefed1.lemmy.ddenis.info`
    ///   (`GET /api/alpha/user/unread_count` with
    ///   `Authorization: Bearer invalid.token.value`, a syntactically-invalid
    ///   token): HTTP 400,
    ///   `{"code":400,"message":"incorrect_login - problem decoding bearer
    ///   token","status":"Bad Request"}`. `PiefedClient` maps PieFed's
    ///   `message` field verbatim into `ErrorResponse.error`, so the wire value
    ///   is the token PLUS a trailing, route-specific human explanation --
    ///   whereas LemmyKit's own fixture tests use the bare `"incorrect_login"`
    ///   (no suffix). A prefix match covers both shapes without depending on
    ///   PieFed's inconsistent suffix wording.
    private static let authCodePrefixes: [String] = ["not_logged_in", "incorrect_login"]

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
            // HTTP 400 carrying a Lemmy error body (e.g. not_logged_in) or a
            // PieFed one mapped through PiefedClient (e.g. incorrect_login,
            // possibly suffixed -- see authCodePrefixes' doc comment).
            return authCodePrefixes.contains { errorResponse.error.hasPrefix($0) }
        case let .unknownServerError(httpStatusCode, _):
            // v4 GET /account rejects an invalid token with 401. A bare 403 is
            // WAF/CDN, NOT auth -- excluded here on purpose.
            return httpStatusCode == 401
        case .network, .failedToDeserializeResponse, .unknown, .unsupportedByDialect:
            return false
        }
    }
}
