//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Recognizes loops.video share URLs (`https://loops.video/v/<shortcode>`) and
/// resolves them to a playable HLS/mp4 stream via loops.video's public video API
/// (`https://<host>/api/v1/video/<numericId>`).
///
/// loops.video is the Pixelfed team's short-video platform. It is the source host,
/// so calling its own API matches Spud's posture of talking to the content source
/// rather than a third-party aggregator; recognition is preference-free and there
/// is no proxy. Only the `/v/<shortcode>` share form is claimed — profiles
/// (`/@user`), embeds (`/embed/...`), and other shapes fall through to the browser.
///
/// This file deliberately does NOT `import SpudUtilKit`: that module exports a
/// same-named `VideoHost` enum which would shadow the seam protocol, so it conforms
/// to the bare `VideoHost` like ``StreamableVideoHost``.
public struct LoopsVideoHost: VideoHost {
    public let kind: VideoHostKind = .loops

    private let fetch: @Sendable (URL) async -> Data?

    /// - Parameter fetch: injected so tests can stub the API response; `nil`
    ///   (the production default) uses ``defaultFetch``, which sends a browser-like
    ///   User-Agent because loops.video sits behind a WAF that 403s requests without
    ///   one (the same class of workaround as `ImageService`'s custom UA for nginx
    ///   denylists — see `AppUserAgent` — but loops.video needs an actual browser
    ///   token, not the plain `Spud/<version>` string). Defaulting to `nil` keeps
    ///   `defaultFetch` private (a public init's default argument may not reference
    ///   private state).
    public init(fetch: (@Sendable (URL) async -> Data?)? = nil) {
        self.fetch = fetch ?? LoopsVideoHost.defaultFetch
    }

    public func recognize(_ url: URL) -> VideoHostMatch? {
        guard let host = url.host()?.lowercased(),
              host == "loops.video" || host == "www.loops.video"
        else {
            return nil
        }

        let parts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        guard parts.count == 2, parts[0] == "v" else {
            return nil
        }
        let shortcode = parts[1]
        // Only claim the URL when the shortcode decodes to a numeric id; a malformed
        // shortcode should classify as an external link, not a dead inline video.
        guard LoopsHashid.decode(shortcode) != nil else {
            return nil
        }
        return VideoHostMatch(kind: .loops, identifier: shortcode, pageUrl: url)
    }

    public func resolve(_ match: VideoHostMatch) async throws -> ResolvedVideo {
        guard match.kind == .loops,
              let numericId = LoopsHashid.decode(match.identifier),
              let host = match.pageUrl.host(),
              let apiUrl = URL(string: "https://\(host)/api/v1/video/\(numericId)")
        else {
            throw VideoHostResolutionError.unresolvable
        }

        guard let data = await fetch(apiUrl) else {
            throw VideoHostResolutionError.network
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw VideoHostResolutionError.decoding
        }

        // Prefer the HLS master playlist so AVPlayer can adapt bitrate; fall back to
        // the progressive mp4. A still-processing video has a null `src_url`; both
        // null means nothing is playable yet.
        let streamUrlString = response.media?.hlsUrl ?? response.media?.srcUrl
        guard let streamUrlString, let streamUrl = URL(string: streamUrlString) else {
            throw VideoHostResolutionError.noPlayableFile
        }

        return ResolvedVideo(
            streamUrl: streamUrl,
            posterUrl: response.media?.thumbnail.flatMap { URL(string: $0) },
            title: response.caption
        )
    }

    /// Production fetch. loops.video's WAF returns 403 for requests without a
    /// browser-like User-Agent, so this sends one; tests inject their own fetch and
    /// never touch the network.
    private static let defaultFetch: @Sendable (URL) async -> Data? = { url in
        var request = URLRequest(url: url)
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        return try? await URLSession.shared.data(for: request).0
    }

    /// A current mobile-Safari User-Agent — enough to satisfy loops.video's WAF,
    /// which rejects the default `CFNetwork/...` and plain `Spud/<version>` tokens.
    private static let browserUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) "
            + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    /// The `VideoResource` shape loops-server returns from `GET /api/v1/video/<id>`.
    private struct Response: Decodable {
        struct Media: Decodable {
            let srcUrl: String?
            let hlsUrl: String?
            let thumbnail: String?

            enum CodingKeys: String, CodingKey {
                case srcUrl = "src_url"
                case hlsUrl = "hls_url"
                case thumbnail
            }
        }

        let caption: String?
        let media: Media?
    }
}
