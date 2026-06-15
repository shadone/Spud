//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Conservative, pattern-only de-AMP. Reconstructs the canonical URL from
/// `*.cdn.ampproject.org/c/[s/]<host>/<path>` and strips the `amp=...` query
/// flag. It deliberately avoids `/amp/` path or `amp.` subdomain heuristics,
/// which need a page fetch to resolve safely (out of scope; see the spec).
public struct DeAMPStep: URLRewriteStep {
    public init() { }

    public func apply(_ url: URL, config: URLSanitizerConfig) -> URL {
        guard config.deAMP else { return url }
        if let reconstructed = Self.reconstructFromCdn(url) {
            return reconstructed
        }
        return Self.strippingAmpFlag(url)
    }

    private static func reconstructFromCdn(_ url: URL) -> URL? {
        guard
            let host = url.host?.lowercased(),
            host.hasSuffix("cdn.ampproject.org")
        else {
            return nil
        }
        // Path: /c/s/<host>/<rest...>  (s => https)  or  /c/<host>/<rest...> (http)
        var segments = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard segments.first == "c" else { return nil }
        segments.removeFirst()
        let scheme: String
        if segments.first == "s" {
            scheme = "https"
            segments.removeFirst()
        } else {
            scheme = "http"
        }
        guard !segments.isEmpty else { return nil }
        let rebuilt = "\(scheme)://" + segments.joined(separator: "/")
        return URL(string: rebuilt)
    }

    private static func strippingAmpFlag(_ url: URL) -> URL {
        guard
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let items = components.queryItems, !items.isEmpty
        else {
            return url
        }
        let kept = items.filter { $0.name.lowercased() != "amp" }
        guard kept.count != items.count else { return url }
        components.queryItems = kept.isEmpty ? nil : kept
        return components.url ?? url
    }
}
