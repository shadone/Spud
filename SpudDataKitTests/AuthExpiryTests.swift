//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import Testing
@testable import SpudDataKit

struct AuthExpiryTests {
    private func errorResponse(_ code: String) -> Components.Schemas.ErrorResponse {
        Components.Schemas.ErrorResponse(error: code)
    }

    @Test
    func unauthorizedIsAuthExpiry() {
        #expect(AuthExpiry.isAuthExpiry(LemmyApiError.unauthorized(message: nil)))
    }

    @Test
    func notLoggedInServerErrorIsAuthExpiry() {
        #expect(AuthExpiry.isAuthExpiry(LemmyApiError.serverError(errorResponse("not_logged_in"))))
    }

    @Test
    func unknownServer401IsAuthExpiry() {
        #expect(AuthExpiry.isAuthExpiry(LemmyApiError.unknownServerError(httpStatusCode: 401, error: nil)))
    }

    @Test
    func unknownServer403IsNotAuthExpiry() {
        // The whole point: a bare WAF/CDN 403 must never trip the flag.
        #expect(!AuthExpiry.isAuthExpiry(LemmyApiError.unknownServerError(httpStatusCode: 403, error: nil)))
    }

    @Test
    func rateLimitServerErrorIsNotAuthExpiry() {
        #expect(!AuthExpiry.isAuthExpiry(LemmyApiError.serverError(errorResponse("rate_limit_error"))))
    }

    @Test
    func networkAndUnknownAreNotAuthExpiry() {
        #expect(!AuthExpiry.isAuthExpiry(LemmyApiError.network(URLError(.timedOut))))
        #expect(!AuthExpiry.isAuthExpiry(LemmyApiError.unknown(URLError(.badURL))))
    }

    @Test
    func piefedIncorrectLoginBareIsAuthExpiry() {
        // The shape LemmyKit's own fixture tests use (no trailing explanation).
        #expect(AuthExpiry.isAuthExpiry(LemmyApiError.serverError(errorResponse("incorrect_login"))))
    }

    @Test
    func piefedIncorrectLoginWithSuffixIsAuthExpiry() {
        // The shape CONFIRMED LIVE (Task 8 probe): `curl -A 'Mozilla/5.0' -H
        // 'Authorization: Bearer invalid.token.value'
        // https://piefed1.lemmy.ddenis.info/api/alpha/user/unread_count` returned
        // HTTP 400, body `{"code":400,"message":"incorrect_login - problem
        // decoding bearer token","status":"Bad Request"}`. LemmyKit's
        // `PiefedClient` maps `message` verbatim into `ErrorResponse.error`, so
        // the wire value carries the token PLUS a trailing explanation --
        // must still match via `authCodePrefixes`' prefix check.
        #expect(AuthExpiry.isAuthExpiry(
            LemmyApiError.serverError(errorResponse("incorrect_login - problem decoding bearer token"))
        ))
    }

    @Test
    func piefedUnrelatedErrorCodeIsNotAuthExpiry() {
        #expect(!AuthExpiry.isAuthExpiry(LemmyApiError.serverError(errorResponse("not_yet_implemented"))))
    }

    @Test
    func unwrapsLemmyServiceErrorWrapper() {
        // getSiteInfo throws LemmyServiceError(from:), so the classifier must see through .apiError.
        let wrapped = LemmyServiceError.apiError(.unauthorized(message: nil))
        #expect(AuthExpiry.isAuthExpiry(wrapped))
        let wrapped403 = LemmyServiceError.apiError(.unknownServerError(httpStatusCode: 403, error: nil))
        #expect(!AuthExpiry.isAuthExpiry(wrapped403))
    }
}
