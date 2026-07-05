//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit

/// Recognizes PeerTube video URLs (reusing ``VideoLinkParser``'s shape heuristic)
/// and resolves them to a playable stream via the instance's REST API
/// (`https://<instance>/api/v1/videos/<id>`).
///
/// PeerTube is federated, so recognition is a URL-shape heuristic with no host
/// allowlist: a false positive resolves against a non-PeerTube API, fails to
/// decode, and falls back to opening the page in the browser. The instance API is
/// the video's own source host, consistent with Spud's posture of talking to the
/// content source rather than a third-party aggregator.
///
/// `VideoHost` is qualified as `SpudDataKit.VideoHost` because `import SpudUtilKit`
/// also brings a same-named enum (`VideoLinkParser`'s host kind) into scope.
public struct PeerTubeVideoHost: SpudDataKit.VideoHost {
    public let kind: VideoHostKind = .peertube

    private let fetch: @Sendable (URL) async -> Data?

    /// - Parameter fetch: injected so tests can stub the API response.
    public init(fetch: @escaping @Sendable (URL) async -> Data? = { url in
        try? await URLSession.shared.data(from: url).0
    }) {
        self.fetch = fetch
    }

    public func recognize(_ url: URL) -> VideoHostMatch? {
        guard let link = VideoLinkParser.parse(url), link.host == .peertube else {
            return nil
        }
        return VideoHostMatch(kind: .peertube, identifier: link.videoId, pageUrl: url)
    }

    public func resolve(_ match: VideoHostMatch) async throws -> ResolvedVideo {
        guard match.kind == .peertube,
              let host = match.pageUrl.host(),
              let apiUrl = URL(string: "https://\(host)/api/v1/videos/\(match.identifier)")
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
        let posterPath = response.previewPath ?? response.thumbnailPath
        let posterUrl = posterPath.flatMap { URL(string: "https://\(host)\($0)") }

        return ResolvedVideo(streamUrl: streamUrl, posterUrl: posterUrl, title: response.name)
    }

    /// Prefer the highest-resolution progressive mp4 (from `files` or the HLS
    /// playlists' own files); fall back to an HLS `.m3u8` playlist that AVPlayer
    /// streams natively. Throw `.noPlayableFile` if neither exists.
    private static func playableStreamUrl(from response: Response) throws -> URL {
        let progressive = (response.files ?? [])
            + (response.streamingPlaylists ?? []).flatMap { $0.files ?? [] }
        let best = progressive
            .compactMap { file -> (url: String, res: Int)? in
                guard let url = file.fileUrl else { return nil }
                return (url, file.resolution?.id ?? 0)
            }
            .max { $0.res < $1.res }

        if let best, let url = URL(string: best.url) {
            return url
        }
        if let playlist = (response.streamingPlaylists ?? []).compactMap(\.playlistUrl).first,
           let url = URL(string: playlist)
        {
            return url
        }
        throw VideoHostResolutionError.noPlayableFile
    }

    private struct Response: Decodable {
        struct Resolution: Decodable {
            let id: Int?
        }

        struct File: Decodable {
            let fileUrl: String?
            let resolution: Resolution?
        }

        struct StreamingPlaylist: Decodable {
            let playlistUrl: String?
            let files: [File]?
        }

        let name: String?
        let thumbnailPath: String?
        let previewPath: String?
        let files: [File]?
        let streamingPlaylists: [StreamingPlaylist]?
    }
}
