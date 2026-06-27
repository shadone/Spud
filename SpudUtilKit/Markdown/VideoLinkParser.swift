//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

public enum VideoHost: Equatable, Sendable {
    case youtube
    case invidious
    case peertube
}

/// A recognized video link and the derived resources to enrich its preview.
public struct VideoLink: Equatable, Sendable {
    public let host: VideoHost
    public let videoId: String
    /// Locally-derivable thumbnail (YouTube/Invidious). nil for PeerTube (its
    /// thumbnail comes from the oEmbed response).
    public let thumbnailURL: URL?
    /// The host's oEmbed endpoint for this link, used to fetch the title.
    public let oEmbedURL: URL?
}

/// Classifies a URL as a known video link. Pure and side-effect free.
///
/// YouTube is matched by host. Invidious and PeerTube are matched by URL *shape*
/// (there is no instance allowlist) — a false positive merely yields an oEmbed
/// fetch that fails and a card that degrades to anchor text + host.
public enum VideoLinkParser {
    private static let youTubeHosts: Set<String> = [
        "youtube.com", "www.youtube.com", "m.youtube.com",
        "music.youtube.com", "youtube-nocookie.com", "www.youtube-nocookie.com",
    ]

    public static func parse(_ url: URL) -> VideoLink? {
        guard
            let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
            let host = url.host?.lowercased()
        else {
            return nil
        }
        let segments = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)

        // YouTube (definitive, by host). youtu.be carries the id as the sole path
        // segment; require exactly one so `/youtu.be/<id>/extra` doesn't match.
        if host == "youtu.be", segments.count == 1, isYouTubeId(segments[0]) {
            return youTube(id: segments[0])
        }
        if youTubeHosts.contains(host), segments.first == "watch", let id = queryValue("v", url), isYouTubeId(id) {
            return youTube(id: id)
        }
        // YouTube /embed/<id> (iframe form). oEmbed 404s on /embed, so youTube(id:)
        // rebuilds the canonical watch URL for the oEmbed url= param.
        if youTubeHosts.contains(host), segments.count == 2, segments[0] == "embed", isYouTubeId(segments[1]) {
            return youTube(id: segments[1])
        }

        // redirect.invidious.io is a privacy redirect that points at real YouTube
        // videos by id; it is NOT a hostable Invidious instance (its /oembed and
        // /vi/<id>.jpg fail), so treat it as YouTube. Must precede the generic
        // Invidious heuristic below.
        if host == "redirect.invidious.io" {
            if segments.first == "watch", let id = queryValue("v", url), isYouTubeId(id) {
                return youTube(id: id)
            }
            if segments.count == 2, segments[0] == "embed", isYouTubeId(segments[1]) {
                return youTube(id: segments[1])
            }
        }

        // Invidious (heuristic): non-YouTube host, /watch?v=<yt-id>.
        if segments.first == "watch", let id = queryValue("v", url), isYouTubeId(id) {
            return VideoLink(
                host: .invidious,
                videoId: id,
                thumbnailURL: URL(string: "https://\(host)/vi/\(id)/hqdefault.jpg"),
                oEmbedURL: oEmbedURL(host: host, path: "/oembed", original: url)
            )
        }

        // PeerTube (heuristic): /w/<id> or /videos/watch/<uuid>.
        if segments.count == 2, segments[0] == "w", isPeerTubeId(segments[1]) {
            return peerTube(id: segments[1], host: host, original: url)
        }
        if segments.count == 3, segments[0] == "videos", segments[1] == "watch", isPeerTubeId(segments[2]) {
            return peerTube(id: segments[2], host: host, original: url)
        }

        return nil
    }

    private static func youTube(id: String) -> VideoLink {
        // YouTube's oEmbed endpoint 404s on the /embed form and is most reliable on
        // the canonical watch URL, so always build url= from the id (never `original`).
        let canonicalWatchURL = URL(string: "https://www.youtube.com/watch?v=\(id)")
        return VideoLink(
            host: .youtube,
            videoId: id,
            thumbnailURL: URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg"),
            oEmbedURL: oEmbedURL(host: "www.youtube.com", path: "/oembed", original: canonicalWatchURL)
        )
    }

    private static func peerTube(id: String, host: String, original: URL) -> VideoLink {
        VideoLink(
            host: .peertube,
            videoId: id,
            thumbnailURL: nil,
            oEmbedURL: oEmbedURL(host: host, path: "/services/oembed", original: original)
        )
    }

    /// `https://<host><path>?url=<original>&format=json`. Returns nil if `original`
    /// is nil (the canonical YouTube watch URL is built from the id and can fail).
    private static func oEmbedURL(host: String, path: String, original: URL?) -> URL? {
        guard let original else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        components.queryItems = [
            URLQueryItem(name: "url", value: original.absoluteString),
            URLQueryItem(name: "format", value: "json"),
        ]
        return components.url
    }

    private static func queryValue(_ name: String, _ url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == name }?.value
    }

    /// YouTube ids are exactly 11 chars of [A-Za-z0-9_-].
    private static func isYouTubeId(_ s: String) -> Bool {
        s.count == 11 && s.allSatisfy { $0 == "_" || $0 == "-" || ($0.isASCII && ($0.isLetter || $0.isNumber)) }
    }

    /// PeerTube short ids / UUIDs: word chars + dashes, at least 6 long.
    private static func isPeerTubeId(_ s: String) -> Bool {
        s.count >= 6 && s.allSatisfy { $0 == "-" || ($0.isASCII && ($0.isLetter || $0.isNumber)) }
    }
}
