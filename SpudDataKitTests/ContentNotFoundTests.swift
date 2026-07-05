//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import Testing
@testable import SpudDataKit

struct ContentNotFoundTests {
    private func serverError(_ code: String) -> LemmyApiError {
        .serverError(Components.Schemas.ErrorResponse(error: code, message: nil))
    }

    @Test
    func couldntFindPostMatches() {
        #expect(ContentNotFound.matchesPost(serverError("couldnt_find_post")))
    }

    @Test
    func wrappedCouldntFindPostMatches() {
        #expect(ContentNotFound.matchesPost(LemmyServiceError.apiError(serverError("couldnt_find_post"))))
    }

    @Test
    func couldntLikePostDoesNotMatch() {
        #expect(!ContentNotFound.matchesPost(serverError("couldnt_like_post")))
    }

    @Test
    func rateLimitDoesNotMatch() {
        #expect(!ContentNotFound.matchesPost(serverError("rate_limit_error")))
    }

    @Test
    func networkErrorDoesNotMatch() {
        #expect(!ContentNotFound.matchesPost(URLError(.timedOut)))
    }
}
