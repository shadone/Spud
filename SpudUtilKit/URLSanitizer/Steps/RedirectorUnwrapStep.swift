//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Extracts the real destination from known redirect wrappers, recursing until
/// the URL is stable (capped to avoid loops). Only http(s) targets are
/// unwrapped, so wrappers carrying `javascript:` etc. are left untouched.
public struct RedirectorUnwrapStep: URLRewriteStep {
    public init() { }

    /// Maps a normalized wrapper host to the query-parameter name holding the
    /// real URL.
    private static let wrappers: [String: String] = [
        "google.com": "q",
        "l.facebook.com": "u",
        "lm.facebook.com": "u",
        "out.reddit.com": "url",
        "steamcommunity.com": "url",
    ]

    public func apply(_ url: URL, config: URLSanitizerConfig) -> URL {
        guard config.unwrapRedirectors else { return url }
        var current = url
        for _ in 0..<5 {
            guard let next = Self.unwrapOnce(current) else { break }
            current = next
        }
        return current
    }

    private static func unwrapOnce(_ url: URL) -> URL? {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let host = components.host?.lowercased()
        else {
            return nil
        }
        let baseHost = normalizedHost(host)

        // href.li encodes the target as the raw query string (no key=value), so it is handled separately from the key-based wrappers map.
        if baseHost == "href.li" {
            guard let query = components.query else { return nil }
            return validHTTPURL(query)
        }

        guard
            let param = wrappers[baseHost],
            let value = components.queryItems?.first(where: { $0.name == param })?.value
        else {
            return nil
        }
        return validHTTPURL(value)
    }

    private static func normalizedHost(_ host: String) -> String {
        for label in ["www.", "m.", "mobile."] where host.hasPrefix(label) {
            return String(host.dropFirst(label.count))
        }
        return host
    }

    private static func validHTTPURL(_ string: String) -> URL? {
        guard
            let url = URL(string: string),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else {
            return nil
        }
        return url
    }
}
