//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudUtilKit

struct VideoLinkParserTests {
    private func parse(_ s: String) -> VideoLink? {
        VideoLinkParser.parse(URL(string: s)!)
    }

    @Test
    func youtubeWatch_idFromQuery() throws {
        let v = try #require(parse("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=5"))
        #expect(v.host == .youtube)
        #expect(v.videoId == "dQw4w9WgXcQ")
        #expect(v.thumbnailURL?.absoluteString == "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg")
        #expect(v.oEmbedURL?.host == "www.youtube.com")
        #expect(v.oEmbedURL?.path == "/oembed")
    }

    @Test
    func youtubeShort_idFromPath() throws {
        let v = try #require(parse("https://youtu.be/dQw4w9WgXcQ"))
        #expect(v.host == .youtube)
        #expect(v.videoId == "dQw4w9WgXcQ")
    }

    @Test
    func youtubeNoCookieAndMobileHosts() {
        #expect(parse("https://m.youtube.com/watch?v=dQw4w9WgXcQ")?.host == .youtube)
        #expect(parse("https://www.youtube-nocookie.com/watch?v=dQw4w9WgXcQ")?.host == .youtube)
    }

    @Test
    func invidious_watchShape() throws {
        let v = try #require(parse("https://yewtu.be/watch?v=dQw4w9WgXcQ"))
        #expect(v.host == .invidious)
        #expect(v.videoId == "dQw4w9WgXcQ")
        #expect(v.thumbnailURL?.absoluteString == "https://yewtu.be/vi/dQw4w9WgXcQ/hqdefault.jpg")
        // URLComponents percent-encodes the url= query value but the exact encoding of '?' vs '%3F'
        // is platform-defined; assert on components rather than the raw string.
        let oEmbed = try #require(v.oEmbedURL)
        #expect(oEmbed.host == "yewtu.be")
        #expect(oEmbed.path == "/oembed")
        let oEmbedComponents = try #require(URLComponents(url: oEmbed, resolvingAgainstBaseURL: false))
        let urlParam = try #require(oEmbedComponents.queryItems?.first { $0.name == "url" }?.value)
        #expect(urlParam == "https://yewtu.be/watch?v=dQw4w9WgXcQ")
        #expect(oEmbedComponents.queryItems?.first { $0.name == "format" }?.value == "json")
    }

    @Test
    func peertube_wAndVideosWatch() throws {
        let short = try #require(parse("https://video.example/w/abc123XYZ"))
        #expect(short.host == .peertube)
        #expect(short.videoId == "abc123XYZ")
        #expect(short.thumbnailURL == nil, "PeerTube thumbnail comes from oEmbed, not derivable")
        #expect(short.oEmbedURL?.path == "/services/oembed")

        let long = try #require(parse("https://video.example/videos/watch/9c9de5e8-0a1e-484a-b099-e80766180a6d"))
        #expect(long.host == .peertube)
        #expect(long.videoId == "9c9de5e8-0a1e-484a-b099-e80766180a6d")
    }

    @Test
    func negatives() {
        #expect(parse("https://example.com/article") == nil)
        #expect(parse("https://example.com/image.jpg") == nil)
        #expect(parse("https://lemmy.world/c/games/p/1/slug") == nil)
        #expect(parse("https://example.com/watch?v=short") == nil) // id too short for YT shape
        #expect(parse("https://youtu.be/dQw4w9WgXcQ/extra") == nil) // youtu.be id must be the sole segment
    }
}
