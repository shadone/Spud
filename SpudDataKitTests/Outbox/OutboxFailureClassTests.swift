//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import Testing
@testable import SpudDataKit

struct OutboxFailureClassTests {
    @Test
    func offlineIsTransient() {
        #expect(OutboxFailureClass.classify(LemmyServiceError.requiresAuthentication, isOnline: false) == .transient)
    }

    @Test
    func requiresAuthOnlineIsPermanent() {
        #expect(OutboxFailureClass.classify(LemmyServiceError.requiresAuthentication, isOnline: true) == .permanent)
    }

    @Test
    func timeoutIsTransient() {
        #expect(OutboxFailureClass.classify(URLError(.timedOut), isOnline: true) == .transient)
    }

    @Test
    func unauthorizedApiErrorIsPermanent() {
        #expect(OutboxFailureClass.classify(LemmyApiError.unauthorized(message: nil), isOnline: true) == .permanent)
    }

    @Test
    func failedToDeserializeIsPermanent() {
        let error = LemmyApiError.failedToDeserializeResponse(underlyingError: URLError(.cannotDecodeRawData))
        #expect(OutboxFailureClass.classify(error, isOnline: true) == .permanent)
    }

    @Test
    func wrappedApiErrorClassifiesInner() {
        let error = LemmyServiceError.apiError(.unauthorized(message: nil))
        #expect(OutboxFailureClass.classify(error, isOnline: true) == .permanent)
    }

    @Test
    func serverErrorIsPermanent() {
        let errorResponse = Components.Schemas.ErrorResponse(error: "couldnt_like_post", message: nil)
        let error = LemmyApiError.serverError(errorResponse)
        #expect(OutboxFailureClass.classify(error, isOnline: true) == .permanent)
    }

    @Test
    func rateLimitServerErrorIsTransient() {
        let errorResponse = Components.Schemas.ErrorResponse(error: "rate_limit_error", message: nil)
        let error = LemmyApiError.serverError(errorResponse)
        #expect(OutboxFailureClass.classify(error, isOnline: true) == .transient)
    }

    @Test
    func clientErrorStatusIsPermanent() {
        #expect(OutboxFailureClass.classify(LemmyApiError.unknownServerError(httpStatusCode: 404, error: nil), isOnline: true) == .permanent)
        #expect(OutboxFailureClass.classify(LemmyApiError.unknownServerError(httpStatusCode: 403, error: nil), isOnline: true) == .permanent)
    }

    @Test
    func tooManyRequestsIsTransient() {
        let error = LemmyApiError.unknownServerError(httpStatusCode: 429, error: nil)
        #expect(OutboxFailureClass.classify(error, isOnline: true) == .transient)
    }

    @Test
    func serverFailureStatusIsTransient() {
        let error = LemmyApiError.unknownServerError(httpStatusCode: 503, error: nil)
        #expect(OutboxFailureClass.classify(error, isOnline: true) == .transient)
    }

    @Test
    func requestTimeoutStatusIsTransient() {
        let error = LemmyApiError.unknownServerError(httpStatusCode: 408, error: nil)
        #expect(OutboxFailureClass.classify(error, isOnline: true) == .transient)
    }
}
