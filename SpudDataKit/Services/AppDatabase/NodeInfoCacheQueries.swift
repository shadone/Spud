//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import GRDB

/// One-shot synchronous read over the NodeInfo host->software cache
/// (`NodeInfoCacheRecord`), for a main-actor synchronous caller (e.g.
/// `AccountService.resolvedApiVersion`) that cannot `await` the actor-isolated
/// `NodeInfoService.detect`/`metadata` probe.
public extension AppDatabase {
    /// The cached NodeInfo software for `host`, or nil when the host has never
    /// been probed (or its cache row was never populated). Callers must fail
    /// open on nil — treat it as "unknown", never as "confirmed not PieFed".
    func nodeInfoCachedSoftwareSync(forHost host: String) -> InstanceSoftware? {
        let normalizedHost = NodeInfoService.normalize(host)
        guard !normalizedHost.isEmpty else { return nil }
        let record = try? writer.read { db in
            try NodeInfoCacheRecord.filter(key: normalizedHost).fetchOne(db)
        }
        return record.map { InstanceSoftware(softwareName: $0.softwareName) }
    }
}
