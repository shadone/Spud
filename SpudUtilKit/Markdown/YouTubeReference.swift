//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// A recognized reference to a YouTube video, possibly reached through a wrapper
/// or privacy front-end. The single source of truth for YouTube-video
/// recognition, shared by ``VideoLinkParser`` (previews) and
/// ``FrontEndRewriteStep`` (link rewriting). Pure and side-effect free.
public struct YouTubeReference: Equatable, Sendable {
    /// Where the reference was found.
    public enum SourceKind: Equatable, Sendable {
        /// A canonical YouTube host (`youtube.com` family, `youtu.be`) or the
        /// `redirect.invidious.io` privacy redirect (which points at real YouTube).
        case youtube
        /// A host present in ``YouTubeFrontEndCatalog``.
        case frontEnd(YouTubeFrontEndKind)
        /// An unknown host matched only by the `/watch?v=<id>` shape (best-effort
        /// Invidious, matching the legacy heuristic).
        case frontEndShape
    }

    /// Canonical 11-char YouTube video id.
    public let videoId: String
    /// Lowercased host the reference was found on.
    public let sourceHost: String
    public let sourceKind: SourceKind
    /// Start offset in whole seconds parsed from `t`/`start`/`#t=` (plain integer
    /// forms only), else nil.
    public let timestampSeconds: Int?

    private static let youTubeHosts: Set<String> = [
        "youtube.com", "www.youtube.com", "m.youtube.com",
        "music.youtube.com", "youtube-nocookie.com", "www.youtube-nocookie.com",
    ]

    /// Classifies `url` as a YouTube video reference, or nil.
    public static func extract(from url: URL) -> YouTubeReference? {
        guard
            let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
            let host = url.host?.lowercased()
        else {
            return nil
        }
        let segments = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let timestamp = timestampSeconds(url)

        // Canonical YouTube family, by host.
        if youTubeHosts.contains(host) {
            guard let id = youTubePathId(segments: segments, url: url) else { return nil }
            return YouTubeReference(videoId: id, sourceHost: host, sourceKind: .youtube, timestampSeconds: timestamp)
        }
        // youtu.be short link: id is the sole path segment.
        if host == "youtu.be", segments.count == 1, isYouTubeId(segments[0]) {
            return YouTubeReference(videoId: segments[0], sourceHost: host, sourceKind: .youtube, timestampSeconds: timestamp)
        }
        // redirect.invidious.io: privacy redirect to real YouTube.
        if host == "redirect.invidious.io" {
            guard let id = frontEndPathId(segments: segments, url: url) else { return nil }
            return YouTubeReference(videoId: id, sourceHost: host, sourceKind: .youtube, timestampSeconds: timestamp)
        }
        // Cataloged front-end: /watch?v=<id> or /embed/<id>.
        if let entry = YouTubeFrontEndCatalog.instance(forHost: host),
           let id = frontEndPathId(segments: segments, url: url)
        {
            return YouTubeReference(videoId: id, sourceHost: host, sourceKind: .frontEnd(entry.kind), timestampSeconds: timestamp)
        }
        // Unknown host, /watch?v=<id> shape (best-effort Invidious).
        if segments.first == "watch", let id = queryValue("v", url), isYouTubeId(id) {
            return YouTubeReference(videoId: id, sourceHost: host, sourceKind: .frontEndShape, timestampSeconds: timestamp)
        }
        return nil
    }

    /// YouTube video id from `/watch?v=`, `/embed/<id>`, `/shorts/<id>`,
    /// `/live/<id>`, `/v/<id>`.
    private static func youTubePathId(segments: [String], url: URL) -> String? {
        if segments.first == "watch", let id = queryValue("v", url), isYouTubeId(id) { return id }
        if segments.count == 2, ["embed", "shorts", "live", "v"].contains(segments[0]), isYouTubeId(segments[1]) {
            return segments[1]
        }
        return nil
    }

    /// YouTube video id from a front-end `/watch?v=` or `/embed/<id>` link.
    private static func frontEndPathId(segments: [String], url: URL) -> String? {
        if segments.first == "watch", let id = queryValue("v", url), isYouTubeId(id) { return id }
        if segments.count == 2, segments[0] == "embed", isYouTubeId(segments[1]) { return segments[1] }
        return nil
    }

    private static func timestampSeconds(_ url: URL) -> Int? {
        for name in ["t", "start"] {
            if let raw = queryValue(name, url), let seconds = Int(raw) { return seconds }
        }
        if let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment,
           fragment.hasPrefix("t="), let seconds = Int(fragment.dropFirst(2))
        {
            return seconds
        }
        return nil
    }

    private static func queryValue(_ name: String, _ url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == name }?.value
    }

    /// YouTube ids are exactly 11 chars of `[A-Za-z0-9_-]`.
    private static func isYouTubeId(_ s: String) -> Bool {
        s.count == 11 && s.allSatisfy { $0 == "_" || $0 == "-" || ($0.isASCII && ($0.isLetter || $0.isNumber)) }
    }
}
