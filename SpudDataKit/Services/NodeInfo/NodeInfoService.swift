//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import os

/// Probes and caches an instance's software via NodeInfo. Probe only on
/// explicit engagement; results are cached with a multi-day TTL; every
/// failure (transport, WAF 403, decode, timeout) resolves to `.unknown`
/// and `detect` never throws.
public protocol NodeInfoServiceType: Sendable {
    func detect(host: String, maxAge: TimeInterval) async -> NodeInfoDetection

    /// Full instance metadata (software + usage counters) from a NodeInfo
    /// probe, or `nil` on any failure (transport, decode, timeout) — never
    /// throws. Shares the same host-keyed cache row and TTL as `detect`: one
    /// probe populates the whole row, so calling both never double-fetches.
    func metadata(host: String, maxAge: TimeInterval) async -> InstanceMetadata?
}

public extension NodeInfoServiceType {
    /// Detects with the default 7-day TTL.
    func detect(host: String) async -> NodeInfoDetection {
        await detect(host: host, maxAge: 7 * 24 * 3600)
    }

    /// Fetches metadata with the default 7-day TTL.
    func metadata(host: String) async -> InstanceMetadata? {
        await metadata(host: host, maxAge: 7 * 24 * 3600)
    }

    /// Fail-open default so conformers that model only software detection
    /// (test stubs) need not implement metadata — they report "unknown".
    /// `NodeInfoService` overrides this with the cache-backed implementation;
    /// because `metadata(host:maxAge:)` is a protocol requirement, calls
    /// through `NodeInfoServiceType` dispatch to that override, not here.
    func metadata(host _: String, maxAge _: TimeInterval) async -> InstanceMetadata? {
        nil
    }
}

public protocol HasNodeInfoService {
    var nodeInfoService: NodeInfoServiceType { get }
}

public actor NodeInfoService: NodeInfoServiceType {
    private let fetcher: NodeInfoFetching
    private let appDatabase: AppDatabase
    private let timeout: TimeInterval
    private let logger = Logger(subsystem: "info.ddenis.Spud", category: "NodeInfoService")

    public init(fetcher: NodeInfoFetching, appDatabase: AppDatabase, timeout: TimeInterval = 4) {
        self.fetcher = fetcher
        self.appDatabase = appDatabase
        self.timeout = timeout
    }

    public func detect(host: String, maxAge: TimeInterval) async -> NodeInfoDetection {
        guard let row = await probe(host: host, maxAge: maxAge) else { return .unknown }
        return .known(InstanceSoftware(softwareName: row.softwareName), version: row.softwareVersion)
    }

    public func metadata(host: String, maxAge: TimeInterval) async -> InstanceMetadata? {
        guard let row = await probe(host: host, maxAge: maxAge) else { return nil }
        return InstanceMetadata(
            software: InstanceSoftware(softwareName: row.softwareName),
            version: row.softwareVersion,
            openRegistrations: row.openRegistrations,
            usersTotal: row.usersTotal,
            usersActiveMonth: row.usersActiveMonth,
            usersActiveHalfyear: row.usersActiveHalfyear,
            localPosts: row.localPosts,
            localComments: row.localComments
        )
    }

    /// The one probe both `detect` and `metadata` share: returns the cache row
    /// for `host` — served from cache when it is younger than `maxAge`,
    /// otherwise a single fetch-through-the-seam that populates the WHOLE row
    /// (software + all usage metadata) and caches it. Returns `nil` on an empty
    /// host or ANY failure (transport, decode, timeout) — the caller maps that
    /// to its own fail-open value (`.unknown` / `nil`). Because both accessors
    /// go through here and write/read the same row + TTL, whichever runs first
    /// populates it and the other serves from cache with no second fetch.
    private func probe(host rawHost: String, maxAge: TimeInterval) async -> NodeInfoCacheRecord? {
        let host = Self.normalize(rawHost)
        guard !host.isEmpty else { return nil }

        if let row = try? await appDatabase.writer.read({ db in
            try NodeInfoCacheRecord.filter(key: host).fetchOne(db)
        }), Date().timeIntervalSince(row.fetchedAt) < maxAge {
            return row
        }

        do {
            let fetched = try await withNodeInfoTimeout(seconds: timeout) { [fetcher] in
                try await fetcher.fetch(host: host)
            }
            let record = NodeInfoCacheRecord(
                host: host,
                softwareName: fetched.softwareName,
                softwareVersion: fetched.softwareVersion,
                fetchedAt: Date(),
                openRegistrations: fetched.openRegistrations,
                usersTotal: fetched.usersTotal,
                usersActiveMonth: fetched.usersActiveMonth,
                usersActiveHalfyear: fetched.usersActiveHalfyear,
                localPosts: fetched.localPosts,
                localComments: fetched.localComments
            )
            try? await appDatabase.writer.write { db in
                try record.upsert(db)
            }
            return record
        } catch {
            logger.debug("NodeInfo probe failed for \(host, privacy: .public): \(error, privacy: .public)")
            return nil
        }
    }

    /// Lowercases and strips any scheme/path so a bare host is the cache key.
    static func normalize(_ raw: String) -> String {
        var value = raw.lowercased().trimmingCharacters(in: .whitespaces)
        if let range = value.range(of: "://") { value = String(value[range.upperBound...]) }
        if let slash = value.firstIndex(of: "/") { value = String(value[..<slash]) }
        return value
    }
}
