//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import Testing
@testable import SpudDataKit

/// Tests for ``OfflineWebArchiveStore`` — the durable file + index store for
/// captured external-link web archives.
///
/// Each test injects a temp base directory (so the `.webarchive` files don't
/// touch the App Group container) and a fresh in-memory `AppDatabase`.
struct OfflineWebArchiveStoreTests {
    private let appDatabase: AppDatabase
    private let baseDirectory: URL
    private let store: OfflineWebArchiveStore

    init() throws {
        appDatabase = try AppDatabase.inMemory()
        baseDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("OfflineWebArchiveStoreTests-\(UUID().uuidString)", isDirectory: true)
        store = try OfflineWebArchiveStore(appDatabase: appDatabase, baseDirectory: baseDirectory)
    }

    /// Count of index rows currently in the store.
    private func rowCount() throws -> Int {
        try appDatabase.writer.read { db in
            try OfflineWebArchiveRecord.fetchCount(db)
        }
    }

    // MARK: - Tests

    /// Upserting writes a file on disk AND an index row; the lookup returns the
    /// file URL, and the file's bytes round-trip.
    @Test
    func upsertWritesFileAndRowAndLookupResolves() async throws {
        let url = try #require(URL(string: "https://example.com/article"))
        let payload = Data("hello-archive".utf8)

        await store.upsertWebArchive(url: url, postServerId: 42, title: "Article", data: payload)

        // One index row, carrying the metadata.
        #expect(try rowCount() == 1)
        let record = try #require(try await appDatabase.writer.read { db in
            try OfflineWebArchiveRecord.fetchOne(db)
        })
        #expect(record.url == url.absoluteString)
        #expect(record.postServerId == 42)
        #expect(record.title == "Article")
        #expect(record.byteSize == Int64(payload.count))

        // The lookup resolves to a real file whose bytes match.
        let fileURL = try #require(store.webArchiveFileURLSync(forURL: url))
        let onDisk = try Data(contentsOf: fileURL)
        #expect(onDisk == payload)
        #expect(store.hasWebArchiveSync(forURL: url))
    }

    /// A lookup for a URL that was never captured returns nil (and `has…` false).
    @Test
    func lookupMissingReturnsNil() throws {
        let url = try #require(URL(string: "https://example.com/never-captured"))
        #expect(store.webArchiveFileURLSync(forURL: url) == nil)
        #expect(store.hasWebArchiveSync(forURL: url) == false)
        #expect(store.webArchiveLookupSync(forURL: url) == nil)
    }

    /// The combined lookup returns the file URL AND the stored page title in one
    /// read (the reader uses the title to seed its navigation title).
    @Test
    func lookupReturnsFileURLAndTitle() async throws {
        let url = try #require(URL(string: "https://example.com/article"))
        await store.upsertWebArchive(url: url, postServerId: 7, title: "Headline", data: Data("a".utf8))

        let lookup = try #require(store.webArchiveLookupSync(forURL: url))
        #expect(lookup.title == "Headline")
        #expect(lookup.fileURL == store.webArchiveFileURLSync(forURL: url))
    }

    /// Re-capturing the same URL replaces the row in place (still one row) and
    /// the file holds the new bytes (same hashed name; old content gone).
    @Test
    func recaptureReplacesRowAndFileContents() async throws {
        let url = try #require(URL(string: "https://example.com/article"))

        await store.upsertWebArchive(url: url, postServerId: 1, title: "Old", data: Data("old".utf8))
        let firstURL = try #require(store.webArchiveFileURLSync(forURL: url))

        await store.upsertWebArchive(url: url, postServerId: 2, title: "New", data: Data("newer-bytes".utf8))

        // Still exactly one row (upsert, not insert).
        #expect(try rowCount() == 1)
        let record = try #require(try await appDatabase.writer.read { db in
            try OfflineWebArchiveRecord.fetchOne(db)
        })
        #expect(record.title == "New")
        #expect(record.postServerId == 2)

        // The file holds the new bytes (the SHA256 name is stable, so the same
        // file is overwritten — the stale content is gone).
        let secondURL = try #require(store.webArchiveFileURLSync(forURL: url))
        #expect(secondURL == firstURL)
        #expect(try Data(contentsOf: secondURL) == Data("newer-bytes".utf8))
    }

    /// When the total archive size exceeds the cap, the store evicts oldest-first
    /// (file + row) until back under the cap; the newest captures survive.
    @Test
    func evictionDropsOldestOverTheCap() async throws {
        // Each archive is ~60 MB so three of them (~180 MB) blow past the 150 MB
        // cap; after the third upsert the oldest must be evicted.
        let chunkSize = 60 * 1024 * 1024
        let payload = Data(count: chunkSize)

        let oldest = try #require(URL(string: "https://example.com/oldest"))
        let middle = try #require(URL(string: "https://example.com/middle"))
        let newest = try #require(URL(string: "https://example.com/newest"))

        // Captured in order, each a beat apart so capturedAt ordering is definite.
        await store.upsertWebArchive(url: oldest, postServerId: nil, title: nil, data: payload)
        try await Task.sleep(nanoseconds: 10_000_000)
        await store.upsertWebArchive(url: middle, postServerId: nil, title: nil, data: payload)
        try await Task.sleep(nanoseconds: 10_000_000)
        await store.upsertWebArchive(url: newest, postServerId: nil, title: nil, data: payload)

        // 3 * 60 MB = 180 MB > 150 MB cap. Eviction drops the single oldest
        // (180 - 60 = 120 MB <= cap), leaving the two newest.
        #expect(try rowCount() == 2)
        #expect(store.hasWebArchiveSync(forURL: oldest) == false, "oldest archive should be evicted")
        #expect(store.hasWebArchiveSync(forURL: middle))
        #expect(store.hasWebArchiveSync(forURL: newest))

        // The evicted archive's file is gone from disk too.
        let total = try await appDatabase.writer.read { db in
            try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(byteSize), 0) FROM offlineWebArchive") ?? 0
        }
        #expect(total <= OfflineWebArchiveStore.maxTotalBytes)
    }
}
