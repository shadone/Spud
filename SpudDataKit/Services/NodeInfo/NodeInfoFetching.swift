//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Seam over the NodeInfo network fetch so `NodeInfoService` can be tested
/// without a live host. The production conformer (`LiveNodeInfoFetcher`)
/// wraps the DiasporaNodeInfo package.
public protocol NodeInfoFetching: Sendable {
    /// Fetches `software.name` / `software.version` for `host`, or throws on
    /// any transport / discovery / decode failure.
    func fetch(host: String) async throws -> (softwareName: String, softwareVersion: String?)
}

private struct NodeInfoTimeoutError: Error { }

/// Runs `operation`, throwing `NodeInfoTimeoutError` if it exceeds `seconds`.
func withNodeInfoTimeout<T: Sendable>(
    seconds: TimeInterval,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw NodeInfoTimeoutError()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
