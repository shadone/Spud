//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Rewrites a URL to a configured privacy front-end. For YouTube video links
/// (canonical or any recognized front-end/`/watch?v=` shape) it extracts the
/// video id and rebuilds a grammar-correct `/watch?v=<id>` on the chosen host —
/// so `youtu.be/<id>` and `/shorts/<id>` normalize correctly and, when
/// ``URLSanitizerConfig/rewriteThirdPartyFrontEnds`` is on, an Invidious link can
/// open in Piped. Other services (and non-video YouTube pages) fall back to a
/// host-swap preserving path/query. Matches `www.`/`m.`/`mobile.` subdomains but
/// not arbitrary ones such as `api.twitter.com`.
public struct FrontEndRewriteStep: URLRewriteStep {
    public init() { }

    public func apply(_ url: URL, config: URLSanitizerConfig) -> URL {
        guard config.redirectToFrontEnds else { return url }

        // YouTube video links: id-based, grammar-correct rewrite (canonical always;
        // third-party front-ends only when the flag is on).
        let youtube = config.setting(for: .youtube)
        if youtube.isEnabled, !youtube.host.isEmpty,
           let ref = YouTubeReference.extract(from: url),
           ref.sourceKind == .youtube || config.rewriteThirdPartyFrontEnds,
           let rewritten = watchURL(host: youtube.host, id: ref.videoId, seconds: ref.timestampSeconds)
        {
            return rewritten
        }

        // Generic host-swap for the remaining sources (twitter/reddit/imgur, and
        // non-video youtube.com pages such as channels/playlists).
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

    /// `https://<host>/watch?v=<id>[&t=<seconds>]`.
    private func watchURL(host: String, id: String, seconds: Int?) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/watch"
        var items = [URLQueryItem(name: "v", value: id)]
        if let seconds { items.append(URLQueryItem(name: "t", value: String(seconds))) }
        components.queryItems = items
        return components.url
    }
}
