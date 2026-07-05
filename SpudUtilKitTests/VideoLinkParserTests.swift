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

    private func oEmbedURL(_ v: VideoLink) -> URL? {
        if case let .oEmbed(url) = v.metadataSource { return url }
        return nil
    }

    @Test
    func youtubeWatch_idFromQuery() throws {
        let v = try #require(parse("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=5"))
        #expect(v.host == .youtube)
        #expect(v.videoId == "dQw4w9WgXcQ")
        #expect(v.thumbnailURL?.absoluteString == "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg")
        #expect(oEmbedURL(v)?.host == "www.youtube.com")
        #expect(oEmbedURL(v)?.path == "/oembed")
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
    func youtubeEmbed_idFromPath() throws {
        let v = try #require(parse("https://www.youtube.com/embed/hwq-xr2fDBU"))
        #expect(v.host == .youtube)
        #expect(v.videoId == "hwq-xr2fDBU")
        #expect(v.thumbnailURL?.host == "i.ytimg.com")
        #expect(v.thumbnailURL?.absoluteString == "https://i.ytimg.com/vi/hwq-xr2fDBU/hqdefault.jpg")
        // oEmbed 404s on the /embed form, so the url= param MUST be the canonical watch URL.
        let oEmbed = try #require(oEmbedURL(v))
        #expect(oEmbed.host == "www.youtube.com")
        #expect(oEmbed.path == "/oembed")
        let oEmbedComponents = try #require(URLComponents(url: oEmbed, resolvingAgainstBaseURL: false))
        let urlParam = try #require(oEmbedComponents.queryItems?.first { $0.name == "url" }?.value)
        #expect(urlParam == "https://www.youtube.com/watch?v=hwq-xr2fDBU")
    }

    @Test
    func youtubeOEmbedUrlIsCanonicalWatch_forYoutuBe() throws {
        // youtu.be original must still produce a canonical watch oEmbed url= param.
        let v = try #require(parse("https://youtu.be/dQw4w9WgXcQ"))
        let oEmbed = try #require(oEmbedURL(v))
        let oEmbedComponents = try #require(URLComponents(url: oEmbed, resolvingAgainstBaseURL: false))
        let urlParam = try #require(oEmbedComponents.queryItems?.first { $0.name == "url" }?.value)
        #expect(urlParam == "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    }

    @Test
    func redirectInvidious_watchIsYouTube() throws {
        // redirect.invidious.io is a privacy redirect pointing at real YouTube videos;
        // it is NOT a hostable Invidious instance, so treat it as YouTube content.
        let v = try #require(parse("https://redirect.invidious.io/watch?v=hwq-xr2fDBU"))
        #expect(v.host == .youtube)
        #expect(v.videoId == "hwq-xr2fDBU")
        #expect(v.thumbnailURL?.host == "i.ytimg.com")
        #expect(v.thumbnailURL?.absoluteString == "https://i.ytimg.com/vi/hwq-xr2fDBU/hqdefault.jpg")
        let oEmbed = try #require(oEmbedURL(v))
        #expect(oEmbed.host == "www.youtube.com")
        let oEmbedComponents = try #require(URLComponents(url: oEmbed, resolvingAgainstBaseURL: false))
        let urlParam = try #require(oEmbedComponents.queryItems?.first { $0.name == "url" }?.value)
        #expect(urlParam == "https://www.youtube.com/watch?v=hwq-xr2fDBU")
    }

    @Test
    func redirectInvidious_embedIsYouTube() throws {
        let v = try #require(parse("https://redirect.invidious.io/embed/hwq-xr2fDBU"))
        #expect(v.host == .youtube)
        #expect(v.videoId == "hwq-xr2fDBU")
        #expect(v.thumbnailURL?.absoluteString == "https://i.ytimg.com/vi/hwq-xr2fDBU/hqdefault.jpg")
    }

    @Test
    func invidious_watchShape() throws {
        let v = try #require(parse("https://yewtu.be/watch?v=dQw4w9WgXcQ"))
        #expect(v.host == .invidious)
        #expect(v.videoId == "dQw4w9WgXcQ")
        #expect(v.thumbnailURL?.absoluteString == "https://yewtu.be/vi/dQw4w9WgXcQ/hqdefault.jpg")
        // URLComponents percent-encodes the url= query value but the exact encoding of '?' vs '%3F'
        // is platform-defined; assert on components rather than the raw string.
        let oEmbed = try #require(oEmbedURL(v))
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
        #expect(oEmbedURL(short)?.path == "/services/oembed")

        let long = try #require(parse("https://video.example/videos/watch/9c9de5e8-0a1e-484a-b099-e80766180a6d"))
        #expect(long.host == .peertube)
        #expect(long.videoId == "9c9de5e8-0a1e-484a-b099-e80766180a6d")
    }

    @Test
    func piped_classifiedAsPipedWithStreamsMetadata() throws {
        let v = try #require(parse("https://piped.video/watch?v=dQw4w9WgXcQ"))
        #expect(v.host == .piped)
        #expect(v.videoId == "dQw4w9WgXcQ")
        #expect(v.thumbnailURL == nil, "Piped thumbnail comes from the /streams API, not derivable")
        guard case let .pipedStreams(url) = v.metadataSource else {
            Issue.record("expected .pipedStreams metadata source")
            return
        }
        #expect(url.absoluteString == "https://api.piped.video/streams/dQw4w9WgXcQ")
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
