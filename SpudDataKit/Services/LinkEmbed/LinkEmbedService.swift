//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit

public protocol LinkEmbedServiceType: Sendable {
    /// Resolves preview metadata for a recognized video link, else nil. Caches by
    /// URL. Network/parse failures degrade to the derived thumbnail (no title).
    func embed(for url: URL) async -> LinkEmbed?
}

@MainActor
public protocol HasLinkEmbedService {
    var linkEmbedService: LinkEmbedServiceType { get }
}

public final class LinkEmbedService: LinkEmbedServiceType {
    private let fetch: @Sendable (URL) async -> Data?
    private let cache = LinkEmbedCache()

    public init(fetch: @escaping @Sendable (URL) async -> Data? = { url in
        try? await URLSession.shared.data(from: url).0
    }) {
        self.fetch = fetch
    }

    public func embed(for url: URL) async -> LinkEmbed? {
        guard let video = VideoLinkParser.parse(url) else { return nil }
        if let cached = await cache.value(for: url) { return cached }

        var title: String?
        var thumbnailURL = video.thumbnailURL

        switch video.metadataSource {
        case let .oEmbed(endpoint):
            if let data = await fetch(endpoint) {
                let response = try? JSONDecoder().decode(OEmbedResponse.self, from: data)
                title = response?.title
                if thumbnailURL == nil { thumbnailURL = response?.thumbnailUrl.flatMap(URL.init(string:)) }
            }
        case let .pipedStreams(endpoint):
            if let data = await fetch(endpoint) {
                let response = try? JSONDecoder().decode(PipedStreamsResponse.self, from: data)
                title = response?.title
                if thumbnailURL == nil { thumbnailURL = response?.thumbnailUrl.flatMap(URL.init(string:)) }
            }
        case .none:
            break
        }

        let embed = LinkEmbed(kind: .video, title: title, thumbnailURL: thumbnailURL)
        await cache.set(embed, for: url)
        return embed
    }
}

private struct OEmbedResponse: Decodable {
    let title: String?
    let thumbnailUrl: String?

    enum CodingKeys: String, CodingKey {
        case title
        case thumbnailUrl = "thumbnail_url"
    }
}

/// Piped's `/streams/<id>` response (subset). Piped uses camelCase `thumbnailUrl`,
/// which maps 1:1 under the default key strategy.
private struct PipedStreamsResponse: Decodable {
    let title: String?
    let thumbnailUrl: String?
}

/// Small in-memory cache. An actor for thread-safety; results are cheap to
/// recompute across launches, so no disk persistence in v1.
private actor LinkEmbedCache {
    private var storage: [String: LinkEmbed] = [:]

    func value(for url: URL) -> LinkEmbed? {
        storage[url.absoluteString]
    }

    func set(_ embed: LinkEmbed, for url: URL) {
        storage[url.absoluteString] = embed
    }
}
