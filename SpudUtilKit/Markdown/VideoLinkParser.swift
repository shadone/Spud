//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

public enum VideoHost: Equatable, Sendable {
    case youtube
    case invidious
    case piped
    case peertube
}

/// A recognized video link and the derived resources to enrich its preview.
public struct VideoLink: Equatable, Sendable {
    /// How ``LinkEmbedService`` should fetch this link's title (and, when not
    /// locally derivable, thumbnail).
    public enum MetadataSource: Equatable, Sendable {
        /// oEmbed endpoint (YouTube, Invidious, PeerTube). `{ title, thumbnail_url }`.
        case oEmbed(URL)
        /// Piped `/streams/<id>` API. `{ title, thumbnailUrl }`.
        case pipedStreams(URL)
        /// No remote metadata available (front-end with unknown API host).
        case none
    }

    public let host: VideoHost
    public let videoId: String
    /// Locally-derivable thumbnail (YouTube/Invidious). nil for Piped/PeerTube,
    /// whose thumbnail comes from the metadata response.
    public let thumbnailURL: URL?
    public let metadataSource: MetadataSource
}

/// Classifies a URL as a known video link. Pure and side-effect free.
///
/// YouTube and its front-ends (Invidious/Piped, plus the `/watch?v=` shape
/// fallback) are recognized via ``YouTubeReference``. PeerTube is matched by URL
/// *shape*. A false positive merely yields a metadata fetch that fails and a card
/// that degrades to anchor text + host.
public enum VideoLinkParser {
    public static func parse(_ url: URL) -> VideoLink? {
        if let ref = YouTubeReference.extract(from: url) {
            return videoLink(from: ref)
        }

        guard let host = url.host?.lowercased() else { return nil }
        let segments = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)

        // PeerTube (heuristic): /w/<id> or /videos/watch/<uuid>.
        if segments.count == 2, segments[0] == "w", isPeerTubeId(segments[1]) {
            return peerTube(id: segments[1], host: host, original: url)
        }
        if segments.count == 3, segments[0] == "videos", segments[1] == "watch", isPeerTubeId(segments[2]) {
            return peerTube(id: segments[2], host: host, original: url)
        }
        return nil
    }

    private static func videoLink(from ref: YouTubeReference) -> VideoLink {
        switch ref.sourceKind {
        case .youtube:
            // YouTube's oEmbed 404s on the /embed form and is most reliable on the
            // canonical watch URL, so always build url= from the id.
            let canonicalWatchURL = URL(string: "https://www.youtube.com/watch?v=\(ref.videoId)")
            return VideoLink(
                host: .youtube,
                videoId: ref.videoId,
                thumbnailURL: URL(string: "https://i.ytimg.com/vi/\(ref.videoId)/hqdefault.jpg"),
                metadataSource: oEmbedSource(host: "www.youtube.com", path: "/oembed", original: canonicalWatchURL)
            )

        case .frontEnd(.piped):
            // Privacy-first: resolve title/thumbnail from Piped's own API, never Google.
            let apiHost = YouTubeFrontEndCatalog.instance(forHost: ref.sourceHost)?.apiHost
            let streamsURL = apiHost.flatMap { URL(string: "https://\($0)/streams/\(ref.videoId)") }
            return VideoLink(
                host: .piped,
                videoId: ref.videoId,
                thumbnailURL: nil,
                metadataSource: streamsURL.map { .pipedStreams($0) } ?? .none
            )

        case .frontEnd(.invidious), .frontEndShape:
            // Privacy-first: thumbnail + oEmbed from the Invidious instance itself.
            let watchURL = URL(string: "https://\(ref.sourceHost)/watch?v=\(ref.videoId)")
            return VideoLink(
                host: .invidious,
                videoId: ref.videoId,
                thumbnailURL: URL(string: "https://\(ref.sourceHost)/vi/\(ref.videoId)/hqdefault.jpg"),
                metadataSource: oEmbedSource(host: ref.sourceHost, path: "/oembed", original: watchURL)
            )
        }
    }

    private static func peerTube(id: String, host: String, original: URL) -> VideoLink {
        VideoLink(
            host: .peertube,
            videoId: id,
            thumbnailURL: nil,
            metadataSource: oEmbedSource(host: host, path: "/services/oembed", original: original)
        )
    }

    /// `.oEmbed(https://<host><path>?url=<original>&format=json)`, or `.none` when
    /// `original` is nil.
    private static func oEmbedSource(host: String, path: String, original: URL?) -> VideoLink.MetadataSource {
        guard let original else { return .none }
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        components.queryItems = [
            URLQueryItem(name: "url", value: original.absoluteString),
            URLQueryItem(name: "format", value: "json"),
        ]
        return components.url.map { .oEmbed($0) } ?? .none
    }

    /// PeerTube short ids / UUIDs: word chars + dashes, at least 6 long.
    private static func isPeerTubeId(_ s: String) -> Bool {
        s.count >= 6 && s.allSatisfy { $0 == "-" || ($0.isASCII && ($0.isLetter || $0.isNumber)) }
    }
}
