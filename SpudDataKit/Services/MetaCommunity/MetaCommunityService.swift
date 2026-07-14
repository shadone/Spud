//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit

/// Resolves + classifies + caches the "meta" (about-the-instance) communities
/// for an instance, per account.
public protocol MetaCommunityServiceType: Sendable {
    /// Resolve + classify + cache the meta communities of `host` for the given
    /// account. No-op when the cache is fresher than the service's freshness
    /// window. `siteName` (when known) sharpens name-matching.
    func refreshInstance(host: String, siteName: String?, forAccountKeychainId keychainId: String) async
}

public protocol HasMetaCommunityService {
    var metaCommunityService: MetaCommunityServiceType { get }
}

/// Probes a fixed candidate-name list (`MetaCommunityCandidates.default`)
/// against an instance via the injected `MetaCommunityResolving` seam,
/// classifies each hit with the pure `MetaCommunityClassifier`, and caches the
/// meta-classified ones via `AppDatabase.replaceMetaCommunitiesSync`.
///
/// A refresh is skipped while the cache is still fresh (`freshness` window),
/// and the cache is only overwritten when at least one candidate actually
/// classified as meta — so a transient all-miss pass (e.g. a flaky network
/// blip that fails every lookup) never wipes a previously-good result.
public actor MetaCommunityService: MetaCommunityServiceType {
    private let resolver: MetaCommunityResolving
    private let appDatabase: AppDatabase
    private let freshness: TimeInterval
    private let candidateNames: [String]

    /// Guards against overlapping refreshes for the same (account, host) pair
    /// racing each other (e.g. two screens triggering a refresh at once).
    private var inFlight: Set<String> = []

    public init(
        resolver: MetaCommunityResolving,
        appDatabase: AppDatabase,
        freshness: TimeInterval = 24 * 3600,
        candidateNames: [String] = MetaCommunityCandidates.default
    ) {
        self.resolver = resolver
        self.appDatabase = appDatabase
        self.freshness = freshness
        self.candidateNames = candidateNames
    }

    public func refreshInstance(
        host: String, siteName: String?, forAccountKeychainId keychainId: String
    ) async {
        guard let accountId = appDatabase.accountRowIdSync(forKeychainId: keychainId) else { return }
        let key = "\(accountId)\u{1}\(host)"
        guard !inFlight.contains(key) else { return }

        if let last = appDatabase.metaCommunityFreshnessSync(forAccountId: accountId, instanceHost: host),
           Date().timeIntervalSince(last) < freshness
        {
            return
        }

        inFlight.insert(key)
        defer { inFlight.remove(key) }

        var entries: [MetaCommunityCacheEntry] = []
        for name in candidateNames {
            guard let resolved = await resolver.resolveCandidate(
                name: name, onHost: host, forAccountKeychainId: keychainId
            ) else { continue }
            let classification = MetaCommunityClassifier.classify(
                name: resolved.name, title: resolved.title,
                instanceHost: resolved.instanceHost, siteName: siteName
            )
            guard classification.isMeta else { continue }
            guard !entries.contains(where: { $0.communityActorId == resolved.actorId }) else { continue }
            entries.append(MetaCommunityCacheEntry(
                communityActorId: resolved.actorId,
                confidence: classification.confidence,
                reason: classification.reason
            ))
        }

        // Only overwrite the cache when we found something, so a transient
        // all-miss network pass does not wipe a good prior result.
        guard !entries.isEmpty else { return }
        appDatabase.replaceMetaCommunitiesSync(
            forAccountId: accountId, instanceHost: host, entries: entries
        )
    }
}
