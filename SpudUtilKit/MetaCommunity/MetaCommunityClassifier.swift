//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

public enum MetaConfidence: String, Sendable, Equatable {
    case high
    case low
}

public enum MetaReason: String, Sendable, Equatable {
    case notMeta
    case nameMatchesInstance
    case strongKeyword
    case broadKeyword
}

public struct MetaClassification: Sendable, Equatable {
    public let isMeta: Bool
    public let confidence: MetaConfidence
    public let reason: MetaReason

    public init(isMeta: Bool, confidence: MetaConfidence, reason: MetaReason) {
        self.isMeta = isMeta
        self.confidence = confidence
        self.reason = reason
    }

    public static let notMeta = MetaClassification(
        isMeta: false, confidence: .low, reason: .notMeta
    )
}

/// Decides whether a community is "meta" for its own home instance. Pure: no
/// DB, no account, no I/O. Meta status is intrinsic to (name/title, home host,
/// that host's site name) and does not depend on the viewing account.
public enum MetaCommunityClassifier {
    public static func classify(
        name: String,
        title: String?,
        instanceHost: String,
        siteName: String?
    ) -> MetaClassification {
        let normalizedName = normalizeCollapsed(name)
        let normalizedTitle = title.map(normalizeCollapsed)

        // Tokens from the name only — used for the BROAD keyword set, whose
        // common words (news, general, updates) appear incidentally in titles
        // and would cause false positives if title-matched.
        let nameTokens = Set(wordTokens(name))
        // Tokens from name + title — used for the STRONG (unambiguous) keyword
        // set and for instance-identity matching, where a title hit is
        // high-value and low-noise (e.g. name "offtopic", title "Site
        // Announcements").
        var nameAndTitleTokens = nameTokens
        if let title { nameAndTitleTokens.formUnion(wordTokens(title)) }

        if matchesInstanceIdentity(
            normalizedName: normalizedName,
            normalizedTitle: normalizedTitle,
            tokens: nameAndTitleTokens,
            instanceHost: instanceHost,
            siteName: siteName
        ) {
            return MetaClassification(
                isMeta: true, confidence: .high, reason: .nameMatchesInstance
            )
        }

        if !nameAndTitleTokens.isDisjoint(with: MetaCommunityKeywords.strong)
            || MetaCommunityKeywords.strong.contains(normalizedName)
        {
            return MetaClassification(
                isMeta: true, confidence: .high, reason: .strongKeyword
            )
        }

        if !nameTokens.isDisjoint(with: MetaCommunityKeywords.broad)
            || MetaCommunityKeywords.broad.contains(normalizedName)
        {
            return MetaClassification(
                isMeta: true, confidence: .low, reason: .broadKeyword
            )
        }

        return .notMeta
    }

    private static func matchesInstanceIdentity(
        normalizedName: String,
        normalizedTitle: String?,
        tokens: Set<String>,
        instanceHost: String,
        siteName: String?
    ) -> Bool {
        // Match against the site's human name when known (preferred, reliable).
        if let siteName {
            let normalizedSite = normalizeCollapsed(siteName)
            if !normalizedSite.isEmpty,
               normalizedName == normalizedSite
               || normalizedTitle == normalizedSite
               || tokens.contains(normalizedSite)
            {
                return true
            }
        }

        // Fall back to the instance's primary domain label (the second-to-last
        // dot component): discuss.tchncs.de -> "tchncs", lemmy.world -> "lemmy".
        // Equality only, never substring, so "world" does not match lemmy.world.
        if let label = primaryDomainLabel(instanceHost), !label.isEmpty {
            if normalizedName == label || tokens.contains(label) {
                return true
            }
        }
        return false
    }

    /// The registrable-domain primary label: second-to-last dot component,
    /// normalized. Returns nil for single-label hosts (e.g. "localhost").
    private static func primaryDomainLabel(_ host: String) -> String? {
        let bare = host.split(separator: ":").first.map(String.init) ?? host
        let labels = bare.split(separator: ".").map(String.init)
        guard labels.count >= 2 else { return nil }
        return normalizeCollapsed(labels[labels.count - 2])
    }

    /// Lowercased, alphanumerics only (drops spaces, hyphens, underscores).
    private static func normalizeCollapsed(_ s: String) -> String {
        s.lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init).joined()
    }

    /// Lowercased word tokens split on any non-alphanumeric boundary.
    private static func wordTokens(_ s: String) -> [String] {
        s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
