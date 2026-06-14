//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

/// Per-dataset bookkeeping for the Lemmy Explorer cache (one row per
/// ``ExplorerDataset``): when it was last refreshed and how big it is.
public struct ExplorerDatasetMetaRecord: Codable, Sendable, Equatable {
    public static let databaseTableName = "explorerDatasetMeta"

    /// Matches ``ExplorerDataset/rawValue`` ("instance" / "community").
    public var datasetKey: String
    public var lastFetchedAt: Date?
    public var etag: String?
    public var partCount: Int64?
    public var recordCount: Int64?
    /// Source-side "as of" timestamp, when the crawl exposes one.
    public var sourceUpdatedAt: Date?

    public init(
        datasetKey: String,
        lastFetchedAt: Date? = nil,
        etag: String? = nil,
        partCount: Int64? = nil,
        recordCount: Int64? = nil,
        sourceUpdatedAt: Date? = nil
    ) {
        self.datasetKey = datasetKey
        self.lastFetchedAt = lastFetchedAt
        self.etag = etag
        self.partCount = partCount
        self.recordCount = recordCount
        self.sourceUpdatedAt = sourceUpdatedAt
    }
}

extension ExplorerDatasetMetaRecord: FetchableRecord, PersistableRecord { }
