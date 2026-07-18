//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Which kind of YouTube privacy front-end a host is. Determines how a preview
/// resolves its title/thumbnail: Invidious serves oEmbed + `/vi` thumbnails from
/// its own host; Piped exposes a separate `/streams` API.
public enum YouTubeFrontEndKind: Equatable, Sendable {
    case invidious
    case piped
}

/// A known YouTube privacy front-end instance.
public struct YouTubeFrontEndInstance: Equatable, Sendable {
    public let host: String
    public let kind: YouTubeFrontEndKind
    /// Piped's API host (`kind == .piped` only); nil for Invidious. NOT derivable
    /// from `host` — each Piped instance publishes its own API domain. A wrong
    /// value degrades the preview gracefully (no title/thumbnail) and never
    /// contacts Google.
    public let apiHost: String?

    public init(host: String, kind: YouTubeFrontEndKind, apiHost: String?) {
        self.host = host
        self.kind = kind
        self.apiHost = apiHost
    }
}

/// Built-in registry of known YouTube front-end instances. Like
/// ``FrontEndCatalog``'s default hosts, this list rots over time and is
/// maintained in code; hosts not listed here fall back to ``VideoLinkParser``'s
/// `/watch?v=` shape heuristic (best-effort Invidious).
public enum YouTubeFrontEndCatalog {
    public static let instances: [YouTubeFrontEndInstance] = [
        YouTubeFrontEndInstance(host: "yewtu.be", kind: .invidious, apiHost: nil),
        YouTubeFrontEndInstance(host: "inv.nadeko.net", kind: .invidious, apiHost: nil),
        YouTubeFrontEndInstance(host: "yt.artemislena.eu", kind: .invidious, apiHost: nil),
        // apiHost: piped.video's own opensearch.xml advertises pipedapi.kavin.rocks.
        // api.piped.video has no DNS A record and does not resolve. A wrong value
        // degrades the preview gracefully (no title/thumbnail) and never contacts Google.
        YouTubeFrontEndInstance(host: "piped.video", kind: .piped, apiHost: "pipedapi.kavin.rocks"),
    ]

    /// The apiHost of the catalog's default Piped instance (the first `.piped`
    /// entry), or nil if the catalog carries none. Backs the opt-in
    /// `inlinePlaybackViaPiped` fallback for users whose YouTube front-end is
    /// not a Piped instance.
    public static var defaultPipedApiHost: String? {
        instances.first { $0.kind == .piped }?.apiHost
    }

    /// The catalog entry for `host` (`www.`/`m.` stripped, lowercased), or nil.
    public static func instance(forHost host: String) -> YouTubeFrontEndInstance? {
        let base = baseHost(host.lowercased())
        return instances.first { $0.host == base }
    }

    private static func baseHost(_ host: String) -> String {
        for prefix in ["www.", "m."] where host.hasPrefix(prefix) {
            return String(host.dropFirst(prefix.count))
        }
        return host
    }
}
