//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Observation
import Testing
@testable import Spud

@Observable
private final class ObservableCounter {
    var value: Int = 0
}

@MainActor
struct ObservationStreamTests {
    /// The stream must keep emitting after the observed property changes — not
    /// just deliver the initial value. Regression test for the scheduler being
    /// deallocated as soon as the build closure returned, which left every
    /// `ObservationStream`-bound property one-shot (e.g. the login button stuck
    /// disabled no matter what the user typed).
    @Test
    func values_reemitsAfterObservedChange() async {
        let model = ObservableCounter()
        let stream = ObservationStream.values(of: { model.value })

        // Collected values are mirrored into a box so the test can wait on the
        // stream's progress instead of guessing at a fixed settle delay.
        @MainActor
        final class Collector {
            var values: [Int] = []
        }
        let collector = Collector()
        let collected = Task { @MainActor () -> [Int] in
            for await value in stream {
                collector.values.append(value)
                if collector.values.count == 2 { break }
            }
            return collector.values
        }

        // Wait for the initial value: changing the model before the observation
        // is registered would drop the very re-emission under test.
        await waitUntil("the stream to emit its initial value") { !collector.values.isEmpty }
        model.value = 42

        // Fail fast instead of hanging if the second emission never arrives.
        let timeout = Task { @MainActor in
            try? await Task.sleep(for: defaultWaitTimeout)
            collected.cancel()
        }

        let values = await collected.value
        timeout.cancel()

        #expect(
            values == [0, 42],
            "Expected the initial value followed by the post-change value; got \(values). A single element means the observation was never re-registered."
        )
    }
}
