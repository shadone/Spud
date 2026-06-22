//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import SpudUtilKit

final class WithTimeoutTests: XCTestCase {
    func testReturnsValueWhenOperationFinishesInTime() async throws {
        let value = try await withTimeout(.seconds(10)) { 42 }
        XCTAssertEqual(value, 42)
    }

    func testThrowsTimeoutErrorWhenOperationIsTooSlow() async {
        do {
            _ = try await withTimeout(.milliseconds(20)) {
                try await Task.sleep(for: .seconds(10))
                return 0
            }
            XCTFail("expected TimeoutError")
        } catch {
            XCTAssertEqual(error as? TimeoutError, TimeoutError())
        }
    }

    func testRethrowsOperationError() async {
        struct Boom: Error, Equatable { }
        do {
            _ = try await withTimeout(.seconds(10)) { throw Boom() }
            XCTFail("expected Boom")
        } catch {
            XCTAssertEqual(error as? Boom, Boom())
        }
    }
}
