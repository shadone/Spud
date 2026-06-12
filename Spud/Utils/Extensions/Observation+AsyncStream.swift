//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Observation

enum ObservationStream {
    /// Bridges an `@Observable` property access into an `AsyncStream` of
    /// values. Yields the initial value, then re-yields after every
    /// observed change. The stream stays alive until the consumer drops
    /// it (or the access closure stops touching tracked properties).
    @MainActor
    static func values<Value: Sendable>(
        of access: @escaping @MainActor () -> Value
    ) -> AsyncStream<Value> {
        AsyncStream { continuation in
            let scheduler = ObservationScheduler<Value>(
                continuation: continuation,
                access: access
            )
            // The scheduler's only inbound reference is its `[weak self]`
            // onChange closure, so without an explicit owner it would
            // deallocate the moment this build closure returns — emitting the
            // initial value and then silently never observing again. Tie its
            // lifetime to the stream: the continuation retains this
            // onTermination handler (and thus the scheduler) until the consumer
            // cancels or the stream finishes, at which point it is released and
            // the weak-self onChange chain winds down.
            continuation.onTermination = { [scheduler] _ in
                withExtendedLifetime(scheduler) { }
            }
            scheduler.observe()
        }
    }
}

@MainActor
private final class ObservationScheduler<Value: Sendable>: Sendable {
    private let continuation: AsyncStream<Value>.Continuation
    private let access: @MainActor () -> Value

    init(
        continuation: AsyncStream<Value>.Continuation,
        access: @escaping @MainActor () -> Value
    ) {
        self.continuation = continuation
        self.access = access
    }

    func observe() {
        let value = withObservationTracking {
            access()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        continuation.yield(value)
    }
}
