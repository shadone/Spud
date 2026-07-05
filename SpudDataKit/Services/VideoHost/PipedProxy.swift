//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Rewrites a Piped stream URL (a direct googlevideo `/videoplayback` URL) to go
/// through the Piped instance's own proxy, so Google is never contacted directly.
/// The result always points at the proxy host — never the original.
enum PipedProxy {
    /// - Parameters:
    ///   - streamURL: a direct stream URL from Piped's `/streams` response.
    ///   - proxyPrefix: the response's `proxyUrl` (e.g. `https://pipedproxy.host`).
    /// - Returns: the proxied URL, or nil if either URL cannot be parsed.
    static func rewrite(streamURL: String, proxyPrefix: String) -> URL? {
        guard var comps = URLComponents(string: streamURL), let originalHost = comps.host,
              let proxy = URLComponents(string: proxyPrefix),
              let proxyHost = proxy.host, !proxyHost.isEmpty
        else {
            return nil
        }
        comps.scheme = proxy.scheme ?? "https"
        comps.host = proxyHost
        comps.port = proxy.port
        var items = comps.queryItems ?? []
        items.append(URLQueryItem(name: "host", value: originalHost))
        comps.queryItems = items
        return comps.url
    }
}
