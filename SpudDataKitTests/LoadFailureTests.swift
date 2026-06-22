//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit
import XCTest
@testable import SpudDataKit

final class LoadFailureTests: XCTestCase {
    func testOfflineWhenMonitorReportsOffline() {
        let failure = LoadFailure.classify(URLError(.timedOut), isOnline: false)
        XCTAssertEqual(failure.kind, .offline)
    }

    func testNotConnectedURLErrorIsOffline() {
        let failure = LoadFailure.classify(URLError(.notConnectedToInternet), isOnline: true)
        XCTAssertEqual(failure.kind, .offline)
    }

    func testTimedOutURLErrorIsUnreachable() {
        let failure = LoadFailure.classify(URLError(.timedOut), isOnline: true)
        XCTAssertEqual(failure.kind, .unreachable)
    }

    func testCannotConnectURLErrorIsUnreachable() {
        let failure = LoadFailure.classify(URLError(.cannotConnectToHost), isOnline: true)
        XCTAssertEqual(failure.kind, .unreachable)
    }

    func testTimeoutErrorIsUnreachable() {
        let failure = LoadFailure.classify(TimeoutError(), isOnline: true)
        XCTAssertEqual(failure.kind, .unreachable)
    }

    func testDecodingErrorIsMalformed() {
        let decoding = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "bad"))
        let failure = LoadFailure.classify(decoding, isOnline: true)
        XCTAssertEqual(failure.kind, .malformedResponse)
    }

    func testInternalInconsistencyIsMalformed() {
        let failure = LoadFailure.classify(
            LemmyServiceError.internalInconsistency(description: "unexpected"),
            isOnline: true
        )
        XCTAssertEqual(failure.kind, .malformedResponse)
    }

    func testRequiresAuthenticationIsUnreachable() {
        let failure = LoadFailure.classify(LemmyServiceError.requiresAuthentication, isOnline: true)
        XCTAssertEqual(failure.kind, .unreachable)
    }

    func testUnknownErrorDefaultsToUnreachable() {
        struct Mystery: Error { }
        let failure = LoadFailure.classify(Mystery(), isOnline: true)
        XCTAssertEqual(failure.kind, .unreachable)
    }

    func testDiagnosticsAreNonEmpty() {
        let failure = LoadFailure.classify(URLError(.timedOut), isOnline: true)
        XCTAssertFalse(failure.diagnostics.isEmpty)
    }
}
