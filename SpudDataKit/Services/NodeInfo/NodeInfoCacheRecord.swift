//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

/// Host-keyed cache of a NodeInfo probe result. Distinct from the legacy
/// instance-scoped `NodeInfoRecord`: this row exists before any `instance`
/// row does, so a pre-flight can probe a host the user has not committed to.
/// `fetchedAt` drives the TTL; a stale row is refreshed on the next probe.
struct NodeInfoCacheRecord: Codable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "nodeInfoCache"

    /// Normalized host (lowercased, no scheme/path). Primary key.
    var host: String
    /// Raw NodeInfo `software.name` (mapped to `InstanceSoftware` at read time).
    var softwareName: String
    /// Raw NodeInfo `software.version`, if advertised.
    var softwareVersion: String?
    /// Timestamp of the last successful probe; drives the cache TTL.
    var fetchedAt: Date
}
