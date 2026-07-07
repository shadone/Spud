//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// A single NodeInfo probe result: the software identity plus the usage
/// metadata a compliant NodeInfo document advertises. Every field beyond the
/// software name is optional because a real server may omit it (the spec
/// marks the usage counters optional, and a WAF/older node can report an
/// empty version). `softwareName` is the one guaranteed field — the fetcher
/// throws rather than return an empty name.
public struct FetchedNodeInfo: Sendable, Equatable {
    /// Raw NodeInfo `software.name` (mapped to `InstanceSoftware` downstream).
    public let softwareName: String
    /// Raw `software.version`, or `nil` when the server reports it empty.
    public let softwareVersion: String?
    /// Whether the instance allows open self-registration, if advertised.
    public let openRegistrations: Bool?
    /// Total registered users, if advertised.
    public let usersTotal: Int64?
    /// Users active in the last ~30 days, if advertised.
    public let usersActiveMonth: Int64?
    /// Users active in the last ~180 days, if advertised.
    public let usersActiveHalfyear: Int64?
    /// Local posts authored on this instance, if advertised.
    public let localPosts: Int64?
    /// Local comments authored on this instance, if advertised.
    public let localComments: Int64?

    public init(
        softwareName: String,
        softwareVersion: String?,
        openRegistrations: Bool?,
        usersTotal: Int64?,
        usersActiveMonth: Int64?,
        usersActiveHalfyear: Int64?,
        localPosts: Int64?,
        localComments: Int64?
    ) {
        self.softwareName = softwareName
        self.softwareVersion = softwareVersion
        self.openRegistrations = openRegistrations
        self.usersTotal = usersTotal
        self.usersActiveMonth = usersActiveMonth
        self.usersActiveHalfyear = usersActiveHalfyear
        self.localPosts = localPosts
        self.localComments = localComments
    }
}

/// Seam over the NodeInfo network fetch so `NodeInfoService` can be tested
/// without a live host. The production conformer (`LiveNodeInfoFetcher`)
/// wraps the DiasporaNodeInfo package.
public protocol NodeInfoFetching: Sendable {
    /// Fetches the full NodeInfo metadata for `host`, or throws on any
    /// transport / discovery / decode failure (including an empty software
    /// name).
    func fetch(host: String) async throws -> FetchedNodeInfo
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
