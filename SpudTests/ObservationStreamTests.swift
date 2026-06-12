//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Observation
import XCTest
@testable import Spud

@Observable
private final class ObservableCounter {
    var value: Int = 0
}

@MainActor
final class ObservationStreamTests: XCTestCase {
    /// The stream must keep emitting after the observed property changes — not
    /// just deliver the initial value. Regression test for the scheduler being
    /// deallocated as soon as the build closure returned, which left every
    /// `ObservationStream`-bound property one-shot (e.g. the login button stuck
    /// disabled no matter what the user typed).
    func test_values_reemitsAfterObservedChange() async {
        let model = ObservableCounter()
        let stream = ObservationStream.values(of: { model.value })

        let collected = Task { @MainActor () -> [Int] in
            var values: [Int] = []
            for await value in stream {
                values.append(value)
                if values.count == 2 { break }
            }
            return values
        }

        // Let the stream emit its initial value and register the observation.
        try? await Task.sleep(for: .milliseconds(50))
        model.value = 42

        // Fail fast instead of hanging if the second emission never arrives.
        let timeout = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            collected.cancel()
        }

        let values = await collected.value
        timeout.cancel()

        XCTAssertEqual(
            values,
            [0, 42],
            "Expected the initial value followed by the post-change value; "
                + "got \(values). A single element means the observation was "
                + "never re-registered."
        )
    }
}
