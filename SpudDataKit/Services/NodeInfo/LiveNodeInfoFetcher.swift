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

    public func fetch(host: String) async throws -> (softwareName: String, softwareVersion: String?) {
        let info = try await NodeInfoManager().fetch(for: host)
        let name = info.softwareName
        // `NodeInfo.softwareVersion` is non-optional per the NodeInfo schema (every
        // compliant response reports a version string), but a real-world server can
        // still report it empty. Map that to `nil` so downstream consumers (e.g. the
        // instance-detail badge) can treat "no version" uniformly instead of having to
        // special-case an empty string.
        let version = info.softwareVersion.isEmpty ? nil : info.softwareVersion
        guard !name.isEmpty else { throw MissingSoftwareName() }
        return (name, version)
    }
}
