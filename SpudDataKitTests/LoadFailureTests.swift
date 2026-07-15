//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudUtilKit
import Testing
@testable import SpudDataKit

struct LoadFailureTests {
    @Test
    func offlineWhenMonitorReportsOffline() {
        let failure = LoadFailure.classify(URLError(.timedOut), isOnline: false)
        #expect(failure.kind == .offline)
    }

    @Test
    func notConnectedURLErrorIsOffline() {
        let failure = LoadFailure.classify(URLError(.notConnectedToInternet), isOnline: true)
        #expect(failure.kind == .offline)
    }

    @Test
    func timedOutURLErrorIsUnreachable() {
        let failure = LoadFailure.classify(URLError(.timedOut), isOnline: true)
        #expect(failure.kind == .unreachable)
    }

    @Test
    func cannotConnectURLErrorIsUnreachable() {
        let failure = LoadFailure.classify(URLError(.cannotConnectToHost), isOnline: true)
        #expect(failure.kind == .unreachable)
    }

    @Test
    func timeoutErrorIsUnreachable() {
        let failure = LoadFailure.classify(TimeoutError(), isOnline: true)
        #expect(failure.kind == .unreachable)
    }

    @Test
    func decodingErrorIsMalformed() {
        let decoding = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "bad"))
        let failure = LoadFailure.classify(decoding, isOnline: true)
        #expect(failure.kind == .malformedResponse)
    }

    @Test
    func internalInconsistencyIsUnreachable() {
        let failure = LoadFailure.classify(
            LemmyServiceError.internalInconsistency(description: "unexpected"),
            isOnline: true
        )
        #expect(failure.kind == .unreachable)
    }

    @Test
    func requiresAuthenticationIsUnreachable() {
        let failure = LoadFailure.classify(LemmyServiceError.requiresAuthentication, isOnline: true)
        #expect(failure.kind == .unreachable)
    }

    @Test
    func unknownErrorDefaultsToUnreachable() {
        struct Mystery: Error { }
        let failure = LoadFailure.classify(Mystery(), isOnline: true)
        #expect(failure.kind == .unreachable)
    }

    @Test
    func diagnosticsAreNonEmpty() {
        let failure = LoadFailure.classify(URLError(.timedOut), isOnline: true)
        #expect(!(failure.diagnostics.isEmpty))
    }

    @Test
    func apiErrorWrappingDeserializeFailureIsMalformed() {
        let decoding = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "bad"))
        let failure = LoadFailure.classify(
            LemmyServiceError.apiError(.failedToDeserializeResponse(underlyingError: decoding)),
            isOnline: true
        )
        #expect(failure.kind == .malformedResponse)
    }

    @Test
    func apiErrorWrappingNotConnectedURLErrorIsOffline() {
        let failure = LoadFailure.classify(
            LemmyServiceError.apiError(.network(URLError(.notConnectedToInternet))),
            isOnline: true
        )
        #expect(failure.kind == .offline)
    }

    @Test
    func apiErrorWrappingTimedOutURLErrorIsUnreachable() {
        let failure = LoadFailure.classify(
            LemmyServiceError.apiError(.network(URLError(.timedOut))),
            isOnline: true
        )
        #expect(failure.kind == .unreachable)
    }

    @Test
    func apiErrorUnknownServerErrorIsUnreachable() {
        let failure = LoadFailure.classify(
            LemmyServiceError.apiError(.unknownServerError(httpStatusCode: 500, error: nil)),
            isOnline: true
        )
        #expect(failure.kind == .unreachable)
    }

    @Test
    func unsupportedByInstanceIsNotSupported() {
        let failure = LoadFailure.classify(
            LemmyServiceError.unsupportedByInstance(.imageUpload),
            isOnline: true
        )
        #expect(failure.kind == .notSupported)
    }

    @Test
    func apiErrorUnsupportedByDialectIsNotSupported() {
        let failure = LoadFailure.classify(
            LemmyServiceError.apiError(.unsupportedByDialect(operation: "uploadImage")),
            isOnline: true
        )
        #expect(failure.kind == .notSupported)
    }

    @Test
    func offlineTakesPrecedenceOverNotSupported() {
        // `isOnline: false` short-circuits every other classification, including
        // the new kind — mirrors the existing offline-precedence tests above.
        let failure = LoadFailure.classify(
            LemmyServiceError.unsupportedByInstance(.imageUpload),
            isOnline: false
        )
        #expect(failure.kind == .offline)
    }
}
