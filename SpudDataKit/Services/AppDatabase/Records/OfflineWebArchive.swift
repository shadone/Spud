//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

/// Index row for one captured external-link web archive.
///
/// The archive *bytes* live on disk (a `.webarchive` file in the App Group
/// container — they can be many megabytes), NOT in this row. The row is the
/// queryable index: it maps the captured `url` to its file, carries the page
/// title for display, and records the byte size + capture time so the store can
/// enforce its total-size cap (oldest-first eviction) and the offline reader
/// (slice 2) can look up an archive by link URL.
///
/// One row per distinct `url` (the `url` column is UNIQUE — see migration
/// `v25_offlineWebArchive`). Re-capturing the same URL replaces the row in place
/// and deletes the stale file.
public struct OfflineWebArchiveRecord: Codable, Sendable, Equatable, Identifiable {
    public static let databaseTableName = "offlineWebArchive"

    public var id: Int64?
    /// The captured page's link URL (the external-link post's `url`). Unique:
    /// re-capturing the same link upserts this row rather than duplicating it.
    public var url: String
    /// The originating post's server id, when the capture came from a post.
    /// Nullable so the store stays usable for non-post captures later.
    public var postServerId: Int64?
    /// File name (NOT a full path) of the `.webarchive` under the store's
    /// archives directory. The directory base can move (e.g. tests inject a temp
    /// dir), so only the leaf name is persisted; the absolute URL is recomposed
    /// at read time.
    public var fileName: String
    /// The captured page `<title>`, when WebKit reported one.
    public var title: String?
    /// On-disk size of the archive file, in bytes. Drives the total-size cap.
    public var byteSize: Int64
    /// When the archive was captured. Eviction deletes oldest-`capturedAt` first.
    public var capturedAt: Date

    public init(
        id: Int64? = nil,
        url: String,
        postServerId: Int64?,
        fileName: String,
        title: String?,
        byteSize: Int64,
        capturedAt: Date = Date()
    ) {
        self.id = id
        self.url = url
        self.postServerId = postServerId
        self.fileName = fileName
        self.title = title
        self.byteSize = byteSize
        self.capturedAt = capturedAt
    }
}

extension OfflineWebArchiveRecord: FetchableRecord, MutablePersistableRecord {
    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
