//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CryptoKit
import Foundation
import GRDB
import OSLog

private let logger = Logger.webArchive

/// Durable store for captured external-link web archives.
///
/// Two-part storage: the archive *bytes* are written as `.webarchive` files in a
/// dedicated directory (`OfflineArchives/`) in the App Group container — web
/// archives can be many megabytes, too large for GRDB BLOBs — and an index row
/// per archive lives in the `offlineWebArchive` table (mapping the captured URL
/// to its file, with title / size / capture time). The write side (slice 1)
/// captures + stores; the offline reader (slice 2) looks up an archive by link
/// URL via the `*Sync` helpers here.
///
/// **Size cap.** Total archive bytes are capped at ``maxTotalBytes`` (150 MB).
/// After each upsert, the oldest-`capturedAt` archives are deleted (file + row)
/// until the total is back under the cap.
///
/// **App Group container.** Files live under the same shared container as the
/// database (`group.info.ddenis.Spud.shared`) so they survive relaunch and are
/// reachable by the app. Tests inject a temp `baseDirectory` instead.
///
/// `Sendable`: the GRDB writer is a `DatabaseWriter` (Sendable) and the base
/// directory URL is immutable. File I/O uses the thread-safe `FileManager`.
public final class OfflineWebArchiveStore: Sendable {
    /// Total archive bytes allowed on disk before oldest-first eviction kicks in.
    /// 150 MB — generous enough for a few hundred typical article archives while
    /// keeping the offline cache from growing without bound.
    public static let maxTotalBytes: Int64 = 150 * 1024 * 1024

    /// Subdirectory (under the base directory) holding the `.webarchive` files.
    private static let archivesDirectoryName = "OfflineArchives"

    private let appDatabase: AppDatabase

    /// Directory the `OfflineArchives/` folder is created under. Production uses
    /// the App Group container; tests inject a temp dir.
    private let baseDirectory: URL

    /// - Parameters:
    ///   - appDatabase: The shared GRDB store holding the `offlineWebArchive`
    ///     index table.
    ///   - baseDirectory: The directory under which the `OfflineArchives/` folder
    ///     is created. Defaults to the App Group container (the durable, shared
    ///     location); tests pass a temp dir. Throws if the default container is
    ///     unavailable (same failure mode as `AppDatabase`).
    public init(appDatabase: AppDatabase, baseDirectory: URL? = nil) throws {
        self.appDatabase = appDatabase
        self.baseDirectory = try baseDirectory ?? Self.appGroupContainerURL()
    }

    /// The App Group container URL (where archive files live in production).
    /// Mirrors `AppDatabase.defaultStoreURL`'s container lookup.
    private static func appGroupContainerURL() throws -> URL {
        let appGroupIdentifier = "group.info.ddenis.Spud.shared"
        guard let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        else {
            throw AppDatabaseError.appGroupContainerUnavailable
        }
        return containerURL
    }

    /// Absolute URL of the `OfflineArchives/` directory, created on demand.
    private func archivesDirectory() throws -> URL {
        let directory = baseDirectory.appendingPathComponent(
            Self.archivesDirectoryName,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    /// Deterministic file name for a URL: `<sha256(url)>.webarchive`. Hashing the
    /// URL gives a stable, filesystem-safe leaf name (URLs contain `/`, `?`, etc.)
    /// and lets a lookup recompute the name without hitting the database.
    private static func fileName(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(hex).webarchive"
    }

    // MARK: - Writes

    /// Persist a captured web archive: write the file, upsert the index row,
    /// then enforce the size cap.
    ///
    /// Replaces any prior capture of the same `url` in place — the old file is
    /// deleted and the row updated (the `url` column is UNIQUE). After the write,
    /// ``maxTotalBytes`` is enforced by oldest-first eviction.
    ///
    /// Best-effort: a file-write failure is logged and swallowed (the downloader
    /// treats archiving as non-fatal), leaving the prior state intact.
    ///
    /// - Parameters:
    ///   - url: The captured page's link URL (the index key).
    ///   - postServerId: The originating post's server id, when applicable.
    ///   - title: The captured page title, when known.
    ///   - data: The `.webarchive` bytes to store.
    public func upsertWebArchive(
        url: URL,
        postServerId: Int64?,
        title: String?,
        data: Data
    ) async {
        let fileName = Self.fileName(for: url)
        let urlString = url.absoluteString
        let byteSize = Int64(data.count)

        do {
            let directory = try archivesDirectory()
            let fileURL = directory.appendingPathComponent(fileName, isDirectory: false)

            // Replacing an existing capture: a prior row for this url may point at
            // a DIFFERENT file name only if the hashing changed (it doesn't), but
            // overwrite atomically regardless so a re-capture is a clean replace.
            try data.write(to: fileURL, options: .atomic)

            try await appDatabase.writer.write { db in
                // Look up any existing row for this url so we can delete its stale
                // file if the file name somehow differs (defensive — same url
                // always hashes to the same name today).
                if let existing = try OfflineWebArchiveRecord
                    .filter(Column("url") == urlString)
                    .fetchOne(db)
                {
                    if existing.fileName != fileName {
                        Self.removeFile(named: existing.fileName, in: directory)
                    }
                    var updated = existing
                    updated.postServerId = postServerId
                    updated.fileName = fileName
                    updated.title = title
                    updated.byteSize = byteSize
                    updated.capturedAt = Date()
                    try updated.update(db)
                } else {
                    var record = OfflineWebArchiveRecord(
                        url: urlString,
                        postServerId: postServerId,
                        fileName: fileName,
                        title: title,
                        byteSize: byteSize,
                        capturedAt: Date()
                    )
                    try record.insert(db)
                }
            }

            try await enforceSizeCap(in: directory)
        } catch {
            logger.error("Failed to store web archive for \(urlString, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    /// Delete oldest-`capturedAt` archives (file + row) until the total on-disk
    /// size is back under ``maxTotalBytes``.
    private func enforceSizeCap(in directory: URL) async throws {
        try await appDatabase.writer.write { db in
            var total = try Int64.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(byteSize), 0) FROM offlineWebArchive"
            ) ?? 0
            guard total > Self.maxTotalBytes else { return }

            // Oldest first; stop as soon as the running total drops under the cap.
            let oldest = try OfflineWebArchiveRecord
                .order(Column("capturedAt").asc)
                .fetchAll(db)
            for record in oldest {
                guard total > Self.maxTotalBytes else { break }
                Self.removeFile(named: record.fileName, in: directory)
                try record.delete(db)
                total -= record.byteSize
            }
        }
    }

    /// Best-effort file removal (a missing file is fine — the row is the source
    /// of truth and we're deleting it anyway).
    private static func removeFile(named fileName: String, in directory: URL) {
        let fileURL = directory.appendingPathComponent(fileName, isDirectory: false)
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Reads (slice 2 consumes these)

    /// Synchronous lookup of the on-disk archive file URL for a captured link,
    /// or nil when no archive exists (or the file is missing). The offline reader
    /// (slice 2) loads the returned `.webarchive` into a `WKWebView` offline.
    ///
    /// Synchronous + nonisolated to match the `*Sync` helper convention and so it
    /// is callable from background read contexts.
    public nonisolated func webArchiveFileURLSync(forURL url: URL) -> URL? {
        let urlString = url.absoluteString
        do {
            let fileName: String? = try appDatabase.writer.read { db in
                try OfflineWebArchiveRecord
                    .filter(Column("url") == urlString)
                    .fetchOne(db)?
                    .fileName
            }
            guard let fileName else { return nil }
            let directory = baseDirectory.appendingPathComponent(
                Self.archivesDirectoryName,
                isDirectory: true
            )
            let fileURL = directory.appendingPathComponent(fileName, isDirectory: false)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
            return fileURL
        } catch {
            logger.error("Failed to look up web archive for \(urlString, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Synchronous existence check for a captured link. Cheaper than
    /// ``webArchiveFileURLSync(forURL:)`` when the caller only needs a yes/no
    /// (e.g. deciding whether to show an "available offline" affordance).
    public nonisolated func hasWebArchiveSync(forURL url: URL) -> Bool {
        webArchiveFileURLSync(forURL: url) != nil
    }
}
