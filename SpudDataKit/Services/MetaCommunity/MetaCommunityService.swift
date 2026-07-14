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
    /// window. `siteName` (when known) sharpens name-matching; pass nil to
    /// have the implementation resolve the account's own home site name from
    /// the DB (the right default when `host` IS that account's home
    /// instance — pass an explicit value only when refreshing some other
    /// instance).
    func refreshInstance(host: String, siteName: String?, forAccountKeychainId keychainId: String) async
}

public protocol HasMetaCommunityService {
    var metaCommunityService: MetaCommunityServiceType { get }
}

/// Probes a candidate-name list — the fixed `MetaCommunityCandidates.default`
/// keywords, plus the instance's primary domain label and (when resolvable)
/// its home site name collapsed to a community-name shape, deduplicated —
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

        // The only caller today (`SubscriptionsViewModel`, refreshing its own
        // account's home instance) always passes nil here; resolve the home
        // site's human name from the DB instead of forcing every caller to
        // plumb it through. The explicit parameter stays for a future caller
        // refreshing an instance that ISN'T the account's home site (e.g. a
        // deferred instance-detail screen), where a DB lookup wouldn't apply.
        let resolvedSiteName = siteName ?? appDatabase.homeSiteNameSync(forKeychainId: keychainId)

        var namesToProbe = candidateNames
        // The flagship community named after the instance itself (e.g.
        // "tchncs" on discuss.tchncs.de) is never in the fixed keyword list —
        // probe it explicitly via the same domain label the classifier
        // already recognizes as an identity match.
        if let label = MetaCommunityClassifier.primaryDomainLabel(host), !label.isEmpty,
           !namesToProbe.contains(where: { $0.caseInsensitiveCompare(label) == .orderedSame })
        {
            namesToProbe.insert(label, at: 0)
        }
        // Same idea for a flagship community named after the site's human
        // name rather than its domain (e.g. "lemmyworld" on lemmy.world,
        // whose domain label is just "lemmy").
        if let resolvedSiteName, let token = Self.collapsedSiteNameCandidate(resolvedSiteName),
           !namesToProbe.contains(where: { $0.caseInsensitiveCompare(token) == .orderedSame })
        {
            namesToProbe.append(token)
        }

        var entries: [MetaCommunityCacheEntry] = []
        for name in namesToProbe {
            guard let resolved = await resolver.resolveCandidate(
                name: name, onHost: host, forAccountKeychainId: keychainId
            ) else { continue }
            let classification = MetaCommunityClassifier.classify(
                name: resolved.name, title: resolved.title,
                instanceHost: resolved.instanceHost, siteName: resolvedSiteName
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

    /// Reduces a human site name to the alphanumeric string a same-named
    /// community would use — Lemmy community names permit no spaces or
    /// punctuation, so "Lemmy World" collapses to "lemmyworld", matching a
    /// community actually named that on lemmy.world. Mirrors
    /// `MetaCommunityClassifier`'s own name normalization so a resolved hit
    /// round-trips through `classify`'s site-name identity match. Nil when
    /// the result is empty.
    private static func collapsedSiteNameCandidate(_ siteName: String) -> String? {
        let collapsed = siteName.lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init).joined()
        return collapsed.isEmpty ? nil : collapsed
    }
}
