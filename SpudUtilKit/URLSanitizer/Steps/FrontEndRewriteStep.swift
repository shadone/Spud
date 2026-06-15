//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Rewrites a URL to a configured privacy front-end (host swap, preserving
/// path/query/fragment) when its host matches an enabled service's source
/// domains. Matches `www.`/`m.`/`mobile.` subdomains but not arbitrary ones
/// such as `api.twitter.com`. Generalizes the former `rewritingTwitterToXcancel`.
public struct FrontEndRewriteStep: URLRewriteStep {
    public init() { }

    public func apply(_ url: URL, config: URLSanitizerConfig) -> URL {
        guard config.redirectToFrontEnds else { return url }
        guard
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let host = components.host?.lowercased()
        else {
            return url
        }

        let baseHost: String
        if let label = ["www.", "mobile.", "m."].first(where: { host.hasPrefix($0) }) {
            baseHost = String(host.dropFirst(label.count))
        } else {
            baseHost = host
        }

        for entry in FrontEndCatalog.entries {
            let setting = config.setting(for: entry.service)
            guard setting.isEnabled, !setting.host.isEmpty else { continue }
            guard entry.sourceDomains.contains(baseHost) else { continue }
            components.host = setting.host
            return components.url ?? url
        }
        return url
    }
}
