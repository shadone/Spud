//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Recognizes streamable.com post/embed URLs and resolves them to a CDN mp4 via
/// streamable's public API (`https://api.streamable.com/videos/{shortcode}`).
///
/// streamable is the source host, so calling its API is consistent with Spud's
/// posture of talking to the content source rather than a third-party aggregator.
public struct StreamableVideoHost: VideoHost {
    public let kind: VideoHostKind = .streamable

    private let fetch: @Sendable (URL) async -> Data?

    /// - Parameter fetch: injected so tests can stub the API response.
    public init(fetch: @escaping @Sendable (URL) async -> Data? = { url in
        try? await URLSession.shared.data(from: url).0
    }) {
        self.fetch = fetch
    }

    public func recognize(_ url: URL) -> VideoHostMatch? {
        guard let host = url.host()?.lowercased(),
              host == "streamable.com" || host == "www.streamable.com"
        else {
            return nil
        }

        let parts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        let shortcode: String?
        switch parts.count {
        case 1:
            shortcode = parts[0]
        case 2 where parts[0] == "e" || parts[0] == "o":
            shortcode = parts[1]
        default:
            shortcode = nil
        }

        guard let shortcode, shortcode.allSatisfy({ $0.isLetter || $0.isNumber }) else {
            return nil
        }
        return VideoHostMatch(kind: .streamable, identifier: shortcode, pageUrl: url)
    }

    public func resolve(_ match: VideoHostMatch) async throws -> ResolvedVideo {
        guard match.kind == .streamable,
              let apiUrl = URL(string: "https://api.streamable.com/videos/\(match.identifier)")
        else {
            throw VideoHostResolutionError.unresolvable
        }

        guard let data = await fetch(apiUrl) else {
            throw VideoHostResolutionError.network
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw VideoHostResolutionError.decoding
        }
        // streamable status: 0 uploading, 1 processing, 2 ready, 3 error.
        guard response.status == 2 else {
            throw VideoHostResolutionError.notReady
        }

        let fileUrlString = response.files?["mp4"]?.url ?? response.files?["mp4-mobile"]?.url
        guard let fileUrlString, let streamUrl = Self.normalizedUrl(fileUrlString) else {
            throw VideoHostResolutionError.noPlayableFile
        }

        return ResolvedVideo(
            streamUrl: streamUrl,
            posterUrl: response.thumbnailUrl.flatMap(Self.normalizedUrl),
            title: response.title
        )
    }

    /// streamable returns protocol-relative URLs (`//cdn...`); make them absolute https.
    static func normalizedUrl(_ string: String) -> URL? {
        if string.hasPrefix("//") {
            return URL(string: "https:" + string)
        }
        return URL(string: string)
    }

    private struct Response: Decodable {
        struct File: Decodable {
            let url: String?
        }

        let status: Int?
        let title: String?
        let thumbnailUrl: String?
        let files: [String: File]?

        enum CodingKeys: String, CodingKey {
            case status, title, files
            case thumbnailUrl = "thumbnail_url"
        }
    }
}
