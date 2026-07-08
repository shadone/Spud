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

    // v31 metadata: the usage counters a NodeInfo document advertises. All
    // nullable — a legacy (pre-v31) row and a server that omits usage both
    // read `nil` here. A single probe writes the whole row, so `detect` and
    // `metadata` serve from the same cached fetch.

    /// Whether the instance allows open self-registration, if advertised.
    var openRegistrations: Bool? = nil
    /// Total registered users, if advertised.
    var usersTotal: Int64? = nil
    /// Users active in the last ~30 days, if advertised.
    var usersActiveMonth: Int64? = nil
    /// Users active in the last ~180 days, if advertised.
    var usersActiveHalfyear: Int64? = nil
    /// Local posts authored on this instance, if advertised.
    var localPosts: Int64? = nil
    /// Local comments authored on this instance, if advertised.
    var localComments: Int64? = nil
}
