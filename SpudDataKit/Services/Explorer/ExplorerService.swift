//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import OSLog

private let logger = Logger.explorerService

/// A Lemmy Explorer dataset. `rawValue` is the path segment used by the
/// multipart data API: `GET /data/{rawValue}.json` -> `{ count }`, then
/// `GET /data/{rawValue}/{index}.json` for each part.
public enum ExplorerDataset: String, Sendable, CaseIterable {
    case instances = "instance"
    case communities = "community"
}

public protocol ExplorerServiceType: Sendable {
    /// Seed the directory from the bundle (offline), then — when `autoRefresh` is
    /// on — refresh from the network if the cache is older than `maxAge`. Safe to
    /// call once at launch; cheap when the cache is fresh.
    func startService(autoRefresh: Bool, maxAge: TimeInterval)
    func refreshIfStale(maxAge: TimeInterval) async
    func refreshCommunitiesIfStale(maxAge: TimeInterval) async
    func refresh(_ dataset: ExplorerDataset) async throws
    /// Force a full network refresh of every dataset (instances and communities).
    /// Used by the manual "Update Now" control; throws on the first failure.
    func refreshAll() async throws
}

@MainActor
public protocol HasExplorerService {
    var explorerService: ExplorerServiceType { get }
}

/// Fetches the Lemmy Explorer directory (data.lemmyverse.net) and caches it in
/// GRDB. The community dataset is large (tens of thousands of rows), so refresh
/// streams one part at a time: decode part -> upsert -> release, then prune.
public actor ExplorerService: ExplorerServiceType {
    private let appDatabase: AppDatabase
    private let session: URLSession

    private static let baseURL = URL(string: "https://data.lemmyverse.net/data")!
    public static let defaultMaxAge: TimeInterval = 86400

    /// Guards the on-demand community refresh (triggered when Discover appears) so
    /// two quick opens can't start two concurrent multi-MB downloads: the staleness
    /// check and the refresh are not atomic across `await`, so both could read
    /// "stale" before either updates the meta timestamp.
    private var communitiesRefreshInFlight = false

    public init(appDatabase: AppDatabase, session: URLSession = .shared) {
        self.appDatabase = appDatabase
        self.session = session
    }

    public nonisolated func startService(autoRefresh: Bool, maxAge: TimeInterval) {
        Task { await self.seedAndRefresh(autoRefresh: autoRefresh, maxAge: maxAge) }
    }

    /// First-launch path: seed instances from the bundle (instant, offline), then
    /// — when automatic updates are on — refresh them from the network if older
    /// than `maxAge`. The much larger community set is seeded from the bundle only
    /// — its network refresh is deferred to the Community Explorer (or a manual
    /// ``refreshAll()``) so launch never triggers a multi-MB download.
    private func seedAndRefresh(autoRefresh: Bool, maxAge: TimeInterval) async {
        await seedIfNeeded(.instances)
        if autoRefresh {
            await refreshIfStale(maxAge: maxAge)
        }
        await seedIfNeeded(.communities)
    }

    public func refreshAll() async throws {
        try await refresh(.instances)
        try await refresh(.communities)
    }

    /// Imports any missing bundled seeds without performing a network refresh.
    /// Exposed for tests; the launch path uses ``seedAndRefresh()``.
    func importSeedsIfNeeded() async {
        await seedIfNeeded(.instances)
        await seedIfNeeded(.communities)
    }

    /// Import the bundled seed for `dataset` when its table is empty (fresh
    /// install or DEBUG schema wipe). `lastFetchedAt` is set to the seed's build
    /// time, so an old seed is treated as stale by ``refreshIfStale``.
    private func seedIfNeeded(_ dataset: ExplorerDataset) async {
        do {
            let isEmpty = try await appDatabase.writer.read { db -> Bool in
                switch dataset {
                case .instances: try ExplorerInstanceRecord.fetchCount(db) == 0
                case .communities: try ExplorerCommunityRecord.fetchCount(db) == 0
                }
            }
            guard isEmpty else { return }

            switch dataset {
            case .instances:
                guard let payload = try ExplorerSeed.loadInstances() else {
                    logger.info("No bundled instance seed")
                    return
                }
                let count = payload.records.count
                try await appDatabase.writer.write { db in
                    try ExplorerImporter.upsertInstances(payload.records, stamp: payload.generatedAt, db: db)
                    try ExplorerImporter.updateMeta(
                        datasetKey: dataset.rawValue,
                        stamp: payload.generatedAt,
                        partCount: 0,
                        recordCount: count,
                        db: db
                    )
                }
                logger.info("Seeded \(count) instances from bundle")

            case .communities:
                guard let payload = try ExplorerSeed.loadCommunities() else {
                    logger.info("No bundled community seed")
                    return
                }
                let count = payload.records.count
                try await appDatabase.writer.write { db in
                    try ExplorerImporter.upsertCommunities(payload.records, stamp: payload.generatedAt, db: db)
                    try ExplorerImporter.updateMeta(
                        datasetKey: dataset.rawValue,
                        stamp: payload.generatedAt,
                        partCount: 0,
                        recordCount: count,
                        db: db
                    )
                }
                logger.info("Seeded \(count) communities from bundle")
            }
        } catch {
            logger.error("\(dataset.rawValue, privacy: .public) seed import failed: \(String(describing: error), privacy: .public)")
        }
    }

    public func refreshIfStale(maxAge: TimeInterval = ExplorerService.defaultMaxAge) async {
        do {
            if try await isStale(.instances, maxAge: maxAge) {
                try await refresh(.instances)
            }
        } catch {
            logger.error("Instance directory refresh failed: \(String(describing: error), privacy: .public)")
        }
    }

    public func refreshCommunitiesIfStale(maxAge: TimeInterval = ExplorerService.defaultMaxAge) async {
        guard !communitiesRefreshInFlight else { return }
        communitiesRefreshInFlight = true
        defer { communitiesRefreshInFlight = false }
        do {
            if try await isStale(.communities, maxAge: maxAge) {
                try await refresh(.communities)
            }
        } catch {
            logger.error("Community directory refresh failed: \(String(describing: error), privacy: .public)")
        }
    }

    public func refresh(_ dataset: ExplorerDataset) async throws {
        let stamp = Date()
        let partCount = try await fetchPartCount(dataset)
        logger.info("Refreshing \(dataset.rawValue, privacy: .public) directory (\(partCount) parts)")

        for index in 0..<partCount {
            let data = try await fetchData(partURL(dataset, index: index))
            try await importPart(dataset, data: data, stamp: stamp)
        }

        let recordCount = try await appDatabase.writer.write { db -> Int in
            let count: Int
            switch dataset {
            case .instances:
                try ExplorerImporter.pruneInstances(olderThan: stamp, db: db)
                count = try ExplorerInstanceRecord.fetchCount(db)
            case .communities:
                try ExplorerImporter.pruneCommunities(olderThan: stamp, db: db)
                count = try ExplorerCommunityRecord.fetchCount(db)
            }
            try ExplorerImporter.updateMeta(
                datasetKey: dataset.rawValue,
                stamp: stamp,
                partCount: partCount,
                recordCount: count,
                db: db
            )
            return count
        }
        logger.info("Refreshed \(dataset.rawValue, privacy: .public) directory: \(recordCount) records")
    }

    // MARK: - Private

    private func importPart(_ dataset: ExplorerDataset, data: Data, stamp: Date) async throws {
        let decoder = JSONDecoder()
        switch dataset {
        case .instances:
            let dtos = try decoder.decode([ExplorerInstanceDTO].self, from: data)
            try await appDatabase.writer.write { db in
                try ExplorerImporter.upsertInstances(dtos, stamp: stamp, db: db)
            }
        case .communities:
            let dtos = try decoder.decode([ExplorerCommunityDTO].self, from: data)
            try await appDatabase.writer.write { db in
                try ExplorerImporter.upsertCommunities(dtos, stamp: stamp, db: db)
            }
        }
    }

    private func fetchPartCount(_ dataset: ExplorerDataset) async throws -> Int {
        let url = Self.baseURL.appending(path: "\(dataset.rawValue).json")
        let data = try await fetchData(url)
        return try JSONDecoder().decode(ExplorerMultipartMetadataDTO.self, from: data).count
    }

    private func partURL(_ dataset: ExplorerDataset, index: Int) -> URL {
        Self.baseURL.appending(path: "\(dataset.rawValue)/\(index).json")
    }

    private func fetchData(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard
            let http = response as? HTTPURLResponse,
            (200..<300).contains(http.statusCode)
        else {
            throw ExplorerServiceError.badResponse(url: url)
        }
        return data
    }

    private func isStale(_ dataset: ExplorerDataset, maxAge: TimeInterval) async throws -> Bool {
        try await appDatabase.writer.read { db -> Bool in
            let recordCount: Int
            switch dataset {
            case .instances: recordCount = try ExplorerInstanceRecord.fetchCount(db)
            case .communities: recordCount = try ExplorerCommunityRecord.fetchCount(db)
            }
            // Empty cache (e.g. fresh install or DEBUG schema wipe) is stale.
            if recordCount == 0 { return true }
            guard
                let meta = try ExplorerDatasetMetaRecord.fetchOne(db, key: dataset.rawValue),
                let last = meta.lastFetchedAt
            else {
                return true
            }
            return Date().timeIntervalSince(last) > maxAge
        }
    }
}

public enum ExplorerServiceError: Error, Sendable {
    case badResponse(url: URL)
}
