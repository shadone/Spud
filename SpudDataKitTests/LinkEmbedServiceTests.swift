//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudDataKit

/// Actor-based helpers used instead of Atomic (which is a @propertyWrapper and
/// not usable as Atomic(false)/.value from a @Sendable closure in Swift 6).
private actor Counter {
    private(set) var n = 0
    func bump() {
        n += 1
    }
}

private actor Flag {
    private(set) var value = false
    func set() {
        value = true
    }
}

struct LinkEmbedServiceTests {
    private func youtubeOEmbedJSON(title: String) -> Data {
        #"{"title":"\#(title)","thumbnail_url":"https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg"}"#.data(using: .utf8)!
    }

    @Test
    func youtube_returnsTitleAndDerivedThumbnail() async throws {
        let json = youtubeOEmbedJSON(title: "Never Gonna Give You Up")
        let service = LinkEmbedService { _ in json }
        let result = try await service.embed(for: #require(URL(string: "https://youtu.be/dQw4w9WgXcQ")))
        let embed = try #require(result)
        #expect(embed.kind == .video)
        #expect(embed.title == "Never Gonna Give You Up")
        #expect(embed.thumbnailURL?.absoluteString == "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg")
    }

    @Test
    func nonVideoLink_returnsNilWithoutFetching() async throws {
        let fetched = Flag()
        let service = LinkEmbedService { _ in
            await fetched.set()
            return nil
        }
        let embed = try await service.embed(for: #require(URL(string: "https://example.com/article")))
        #expect(embed == nil)
        let wasFetched = await fetched.value
        #expect(!wasFetched, "must not fetch for a non-video link")
    }

    @Test
    func oEmbedFailure_keepsDerivedThumbnail() async throws {
        let service = LinkEmbedService { _ in nil } // network/JSON failure
        let result = try await service.embed(for: #require(URL(string: "https://youtu.be/dQw4w9WgXcQ")))
        let embed = try #require(result)
        #expect(embed.title == nil)
        #expect(embed.thumbnailURL?.absoluteString == "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg")
    }

    @Test
    func cache_secondCallDoesNotRefetch() async throws {
        let count = Counter()
        let json = youtubeOEmbedJSON(title: "t")
        let service = LinkEmbedService { _ in
            await count.bump()
            return json
        }
        _ = try await service.embed(for: #require(URL(string: "https://youtu.be/dQw4w9WgXcQ")))
        _ = try await service.embed(for: #require(URL(string: "https://youtu.be/dQw4w9WgXcQ")))
        let n = await count.n
        #expect(n == 1)
    }

    @Test
    func piped_returnsTitleAndThumbnailFromStreamsApi() async throws {
        let json = #"{"title":"Some Video","thumbnailUrl":"https://api.piped.video/thumb.jpg"}"#.data(using: .utf8)!
        let service = LinkEmbedService { _ in json }
        let result = try await service.embed(for: #require(URL(string: "https://piped.video/watch?v=dQw4w9WgXcQ")))
        let embed = try #require(result)
        #expect(embed.kind == .video)
        #expect(embed.title == "Some Video")
        #expect(embed.thumbnailURL?.absoluteString == "https://api.piped.video/thumb.jpg")
    }
}
