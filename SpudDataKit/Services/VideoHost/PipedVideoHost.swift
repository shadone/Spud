//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit

/// Recognizes YouTube / Piped video URLs and resolves them to a Piped-PROXIED
/// stream (never a direct googlevideo URL), honoring the user's front-end choice.
///
/// Recognition is preference-free (so every YouTube post classifies as video); the
/// preference gates resolution — a raw youtube.com link resolves only when the
/// user's YouTube front-end is a Piped instance (see ``PipedInstanceResolver``),
/// otherwise resolution throws and playback falls back to the browser.
///
/// `VideoHost` is qualified as `SpudDataKit.VideoHost` because `import SpudUtilKit`
/// also brings a same-named enum into scope.
public struct PipedVideoHost: SpudDataKit.VideoHost {
    public let kind: VideoHostKind = .piped

    private let fetch: @Sendable (URL) async -> Data?
    private let config: URLSanitizerConfig

    /// - Parameters:
    ///   - fetch: injected so tests can stub the API response.
    ///   - config: a Sendable snapshot of the user's URL-sanitizer config, read on
    ///     the main actor by the caller (used only in `resolve`).
    public init(
        fetch: @escaping @Sendable (URL) async -> Data? = { url in
            try? await URLSession.shared.data(from: url).0
        },
        config: URLSanitizerConfig = .default
    ) {
        self.fetch = fetch
        self.config = config
    }

    public func recognize(_ url: URL) -> VideoHostMatch? {
        guard let ref = YouTubeReference.extract(from: url) else { return nil }
        switch ref.sourceKind {
        case .youtube, .frontEnd(.piped):
            return VideoHostMatch(kind: .piped, identifier: ref.videoId, pageUrl: url)
        case .frontEnd(.invidious), .frontEndShape:
            return nil
        }
    }

    public func resolve(_ match: VideoHostMatch) async throws -> ResolvedVideo {
        guard match.kind == .piped,
              let apiHost = PipedInstanceResolver.apiHost(forYouTubePageURL: match.pageUrl, config: config),
              let apiUrl = URL(string: "https://\(apiHost)/streams/\(match.identifier)")
        else {
            throw VideoHostResolutionError.unresolvable
        }

        guard let data = await fetch(apiUrl) else {
            throw VideoHostResolutionError.network
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw VideoHostResolutionError.decoding
        }

        let streamUrl = try Self.playableStreamUrl(from: response)
        return ResolvedVideo(
            streamUrl: streamUrl,
            posterUrl: response.thumbnailUrl.flatMap { URL(string: $0) },
            title: response.title
        )
    }

    /// Privacy invariant: return only a Piped-proxied stream, never a direct
    /// googlevideo URL. Prefer the HLS master (Piped already proxies it, and it is
    /// adaptive); otherwise proxy the best progressive muxed stream through
    /// `proxyUrl`; refuse if neither is possible.
    private static func playableStreamUrl(from response: Response) throws -> URL {
        if let hls = response.hls, let url = URL(string: hls) {
            return url
        }
        guard let proxyPrefix = response.proxyUrl, !proxyPrefix.isEmpty else {
            throw VideoHostResolutionError.noPlayableFile
        }
        let bestMuxed = (response.videoStreams ?? [])
            .filter { $0.videoOnly == false }
            .compactMap { stream -> (url: String, bitrate: Int)? in
                guard let url = stream.url else { return nil }
                return (url, stream.bitrate ?? 0)
            }
            .max { $0.bitrate < $1.bitrate }
        if let bestMuxed, let proxied = PipedProxy.rewrite(streamURL: bestMuxed.url, proxyPrefix: proxyPrefix) {
            return proxied
        }
        throw VideoHostResolutionError.noPlayableFile
    }

    private struct Response: Decodable {
        struct VideoStream: Decodable {
            let url: String?
            let videoOnly: Bool?
            let bitrate: Int?
        }

        let title: String?
        let thumbnailUrl: String?
        let hls: String?
        let proxyUrl: String?
        let videoStreams: [VideoStream]?
    }
}
