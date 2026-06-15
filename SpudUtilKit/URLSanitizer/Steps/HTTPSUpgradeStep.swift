//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Upgrades `http://` URLs to `https://`. Skips hosts that commonly do not
/// serve HTTPS: IP literals, `localhost`, and `.onion`.
public struct HTTPSUpgradeStep: URLRewriteStep {
    public init() { }

    public func apply(_ url: URL, config: URLSanitizerConfig) -> URL {
        guard config.upgradeToHTTPS else { return url }
        guard
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme?.lowercased() == "http",
            let host = components.host?.lowercased()
        else {
            return url
        }

        if host == "localhost" || host.hasSuffix(".onion") || isIPLiteral(host) {
            return url
        }

        components.scheme = "https"
        return components.url ?? url
    }

    private func isIPLiteral(_ host: String) -> Bool {
        // IPv6 literals arrive bracket-stripped from URLComponents.host.
        if host.contains(":") { return true }
        let labels = host.split(separator: ".")
        return labels.count == 4 && labels.allSatisfy { label in
            !label.isEmpty && label.allSatisfy(\.isNumber)
        }
    }
}
