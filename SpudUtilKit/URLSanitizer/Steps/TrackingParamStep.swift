//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Removes tracking query parameters by name (preserving everything else and
/// the path/fragment), plus a few per-domain special cases. `si` is treated as
/// a tracker only on YouTube/Spotify (more conservative than a global rule).
public struct TrackingParamStep: URLRewriteStep {
    public init() { }

    /// Lowercased name prefixes stripped on every host.
    private static let globalPrefixes = ["utm_", "ga_", "pk_", "mtm_", "hsa_"]

    /// Lowercased exact names stripped on every host.
    private static let globalExact: Set<String> = [
        "fbclid", "gclid", "dclid", "gbraid", "wbraid", "msclkid", "twclid",
        "yclid", "igshid", "mc_eid", "mc_cid", "_hsenc", "_hsmi", "vero_id",
        "oly_anon_id", "oly_enc_id", "ref_src", "ref_url", "share_id",
    ]

    public func apply(_ url: URL, config: URLSanitizerConfig) -> URL {
        guard config.stripTrackingParams else { return url }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        let baseHost = (components.host?.lowercased()).map(Self.normalizedHost) ?? ""

        // Amazon: collapse to /dp/<ASIN> or /gp/product/<ASIN> when present.
        if baseHost.hasPrefix("amazon."), let flattened = Self.flattenedAmazonPath(components.path) {
            components.path = flattened
            components.queryItems = nil
            components.fragment = nil
            return components.url ?? url
        }

        guard let items = components.queryItems, !items.isEmpty else { return url }

        let perDomainExact = Self.perDomainExact(for: baseHost)
        let kept = items.filter { item in
            let name = item.name.lowercased()
            if Self.globalExact.contains(name) { return false }
            if perDomainExact.contains(name) { return false }
            if Self.globalPrefixes.contains(where: { name.hasPrefix($0) }) { return false }
            return true
        }

        guard kept.count != items.count else { return url }
        components.queryItems = kept.isEmpty ? nil : kept
        return components.url ?? url
    }

    /// Strips a single `www.`/`m.`/`mobile.` label so per-domain rules match.
    private static func normalizedHost(_ host: String) -> String {
        for label in ["www.", "m.", "mobile."] where host.hasPrefix(label) {
            return String(host.dropFirst(label.count))
        }
        return host
    }

    private static func perDomainExact(for baseHost: String) -> Set<String> {
        switch baseHost {
        case "youtube.com", "youtu.be":
            return ["si", "feature", "pp"]
        case "spotify.com", "open.spotify.com":
            return ["si"]
        default:
            return []
        }
    }

    /// Returns `/dp/<ASIN>` or `/gp/product/<ASIN>` when the path contains an
    /// Amazon product id (10 alphanumerics); otherwise nil.
    private static func flattenedAmazonPath(_ path: String) -> String? {
        let segments = path.split(separator: "/").map(String.init)
        func isASIN(_ s: String) -> Bool {
            s.count == 10 && s.allSatisfy { $0.isLetter || $0.isNumber }
        }
        if let i = segments.firstIndex(of: "dp"), i + 1 < segments.count, isASIN(segments[i + 1]) {
            return "/dp/\(segments[i + 1])"
        }
        if let i = segments.firstIndex(of: "gp"), i + 2 < segments.count,
           segments[i + 1] == "product", isASIN(segments[i + 2])
        {
            return "/gp/product/\(segments[i + 2])"
        }
        return nil
    }
}
