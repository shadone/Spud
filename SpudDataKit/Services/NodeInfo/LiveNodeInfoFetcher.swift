//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import DiasporaNodeInfo
import Foundation

/// Production `NodeInfoFetching` backed by the DiasporaNodeInfo package.
/// Reads via the package's version-agnostic convenience accessors (2.0.0+),
/// so it never needs to branch on the `v2_0`/`v2_1` schema case itself.
public struct LiveNodeInfoFetcher: NodeInfoFetching {
    struct MissingSoftwareName: Error { }

    public init() { }

    public func fetch(host: String) async throws -> FetchedNodeInfo {
        let info = try await NodeInfoManager().fetch(for: host)
        return try Self.map(info)
    }

    /// Maps a decoded `NodeInfo` to `FetchedNodeInfo` via the package's 2.0
    /// version-agnostic convenience accessors, so it never branches on the
    /// `v2_0`/`v2_1` schema case. Factored out of the network `fetch(host:)`
    /// so the pure mapping (including the empty-version normalization and the
    /// empty-name throw) is unit-testable without a live host.
    static func map(_ info: NodeInfo) throws -> FetchedNodeInfo {
        let name = info.softwareName
        guard !name.isEmpty else { throw MissingSoftwareName() }
        // `NodeInfo.softwareVersion` is non-optional per the NodeInfo schema (every
        // compliant response reports a version string), but a real-world server can
        // still report it empty. Map that to `nil` so downstream consumers (e.g. the
        // instance-detail badge) can treat "no version" uniformly instead of having to
        // special-case an empty string.
        let version = info.softwareVersion.isEmpty ? nil : info.softwareVersion
        // `openRegistrations` is a non-optional `Bool` on the accessor, so a live
        // probe always yields a concrete value; the `Bool?` field carries the
        // "not yet probed" absence at the cache/domain layer, never here.
        return FetchedNodeInfo(
            softwareName: name,
            softwareVersion: version,
            openRegistrations: info.openRegistrations,
            usersTotal: info.usersTotal,
            usersActiveMonth: info.usersActiveMonth,
            usersActiveHalfyear: info.usersActiveHalfyear,
            localPosts: info.localPosts,
            localComments: info.localComments
        )
    }
}
