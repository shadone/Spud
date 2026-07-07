//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Live instance metadata surfaced from a NodeInfo probe: the software
/// identity plus the usage counters a compliant node advertises. This is the
/// domain shape `NodeInfoService.metadata(host:)` returns — the cache-record
/// representation (`NodeInfoCacheRecord`) is an implementation detail.
///
/// Every field beyond `software` is optional: the NodeInfo spec marks the
/// usage counters optional, and an un-probed / partially-reporting node leaves
/// them `nil`. Consumers must treat a `nil` (or an overall `nil` metadata)
/// as "unknown" and fail open — never as "zero" or "closed".
public struct InstanceMetadata: Sendable, Equatable {
    /// The recognized (or verbatim `.other`) software the host runs.
    public let software: InstanceSoftware
    /// The software version string, if advertised.
    public let version: String?
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
        software: InstanceSoftware,
        version: String?,
        openRegistrations: Bool?,
        usersTotal: Int64?,
        usersActiveMonth: Int64?,
        usersActiveHalfyear: Int64?,
        localPosts: Int64?,
        localComments: Int64?
    ) {
        self.software = software
        self.version = version
        self.openRegistrations = openRegistrations
        self.usersTotal = usersTotal
        self.usersActiveMonth = usersActiveMonth
        self.usersActiveHalfyear = usersActiveHalfyear
        self.localPosts = localPosts
        self.localComments = localComments
    }
}
