import Foundation
import GRDB
import os

/// Probes and caches an instance's software via NodeInfo. Probe only on
/// explicit engagement; results are cached with a multi-day TTL; every
/// failure (transport, WAF 403, decode, timeout) resolves to `.unknown`
/// and `detect` never throws.
public protocol NodeInfoServiceType: Sendable {
    func detect(host: String, maxAge: TimeInterval) async -> NodeInfoDetection
}

public extension NodeInfoServiceType {
    /// Detects with the default 7-day TTL.
    func detect(host: String) async -> NodeInfoDetection {
        await detect(host: host, maxAge: 7 * 24 * 3600)
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

    public func detect(host rawHost: String, maxAge: TimeInterval) async -> NodeInfoDetection {
        let host = Self.normalize(rawHost)
        guard !host.isEmpty else { return .unknown }

        if let row = try? await appDatabase.writer.read({ db in
            try NodeInfoCacheRecord.filter(key: host).fetchOne(db)
        }), Date().timeIntervalSince(row.fetchedAt) < maxAge {
            return .known(InstanceSoftware(softwareName: row.softwareName), version: row.softwareVersion)
        }

        do {
            let (name, version) = try await withNodeInfoTimeout(seconds: timeout) { [fetcher] in
                try await fetcher.fetch(host: host)
            }
            try? await appDatabase.writer.write { db in
                let record = NodeInfoCacheRecord(
                    host: host, softwareName: name, softwareVersion: version, fetchedAt: Date()
                )
                try record.upsert(db)
            }
            return .known(InstanceSoftware(softwareName: name), version: version)
        } catch {
            logger.debug("NodeInfo probe failed for \(host, privacy: .public): \(error, privacy: .public)")
            return .unknown
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
