//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
@testable import SpudUtilKit

struct WithTimeoutTests {
    @Test
    func returnsValueWhenOperationFinishesInTime() async throws {
        let value = try await withTimeout(.seconds(10)) { 42 }
        #expect(value == 42)
    }

    @Test
    func throwsTimeoutErrorWhenOperationIsTooSlow() async {
        do {
            _ = try await withTimeout(.milliseconds(20)) {
                try await Task.sleep(for: .seconds(10))
                return 0
            }
            Issue.record("expected TimeoutError")
        } catch {
            #expect(error as? TimeoutError == TimeoutError())
        }
    }

    @Test
    func rethrowsOperationError() async {
        struct Boom: Error, Equatable { }
        do {
            _ = try await withTimeout(.seconds(10)) { throw Boom() }
            Issue.record("expected Boom")
        } catch {
            #expect(error as? Boom == Boom())
        }
    }
}
