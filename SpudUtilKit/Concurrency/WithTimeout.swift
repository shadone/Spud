//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Thrown by `withTimeout(_:operation:)` when `operation` does not finish
/// within the allotted duration.
public struct TimeoutError: Error, Equatable {
    public init() { }
}

/// Runs `operation`, throwing `TimeoutError` if it does not complete within
/// `duration`. On either outcome the losing child task is cancelled, so a
/// cooperative `operation` stops promptly on timeout.
public func withTimeout<T: Sendable>(
    _ duration: Duration,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: duration)
            throw TimeoutError()
        }
        defer { group.cancelAll() }
        // The first child to finish wins; `next()` rethrows TimeoutError if the
        // timer fired first, or the operation's value/error otherwise.
        guard let result = try await group.next() else {
            throw TimeoutError()
        }
        return result
    }
}
