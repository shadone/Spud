//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import DiasporaNodeInfo
import Foundation

/// Production `NodeInfoFetching` backed by the DiasporaNodeInfo package.
/// Coalesces the version-specific software projections locally (no dependency
/// on a version-agnostic accessor in the package).
public struct LiveNodeInfoFetcher: NodeInfoFetching {
    struct MissingSoftwareName: Error { }

    public init() { }

    public func fetch(host: String) async throws -> (softwareName: String, softwareVersion: String?) {
        let info = try await NodeInfoManager().fetch(for: host)
        let name = info.v2_1?.software.name ?? info.v2_0?.software.name ?? ""
        let version = info.v2_1?.software.version ?? info.v2_0?.software.version
        guard !name.isEmpty else { throw MissingSoftwareName() }
        return (name, version)
    }
}
