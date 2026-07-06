//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

#if DEBUG
import Foundation

public extension AppDatabase {
    /// UI-test seam: inserts or replaces a `NodeInfoCacheRecord` for `host`
    /// so that `NodeInfoService.detect(host:)` short-circuits with
    /// `PlatformUnsupportedError` instead of making a real network request.
    /// Compiled only in DEBUG builds; `NodeInfoCacheRecord` remains internal.
    func seedNodeInfoCacheForUITests(
        host: String,
        softwareName: String,
        softwareVersion: String?
    ) throws {
        try writer.write { db in
            var record = NodeInfoCacheRecord(
                host: host,
                softwareName: softwareName,
                softwareVersion: softwareVersion,
                fetchedAt: Date()
            )
            try record.upsert(db)
        }
    }
}
#endif
