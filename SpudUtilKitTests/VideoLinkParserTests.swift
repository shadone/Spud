//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import XCTest
@testable import SpudUtilKit

final class VideoLinkParserTests: XCTestCase {
    private func parse(_ s: String) -> VideoLink? {
        VideoLinkParser.parse(URL(string: s)!)
    }

    func test_youtubeWatch_idFromQuery() throws {
        let v = try XCTUnwrap(parse("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=5"))
        XCTAssertEqual(v.host, .youtube)
        XCTAssertEqual(v.videoId, "dQw4w9WgXcQ")
        XCTAssertEqual(v.thumbnailURL?.absoluteString, "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg")
        XCTAssertEqual(v.oEmbedURL?.host, "www.youtube.com")
        XCTAssertEqual(v.oEmbedURL?.path, "/oembed")
    }

    func test_youtubeShort_idFromPath() throws {
        let v = try XCTUnwrap(parse("https://youtu.be/dQw4w9WgXcQ"))
        XCTAssertEqual(v.host, .youtube)
        XCTAssertEqual(v.videoId, "dQw4w9WgXcQ")
    }

    func test_youtubeNoCookieAndMobileHosts() {
        XCTAssertEqual(parse("https://m.youtube.com/watch?v=dQw4w9WgXcQ")?.host, .youtube)
        XCTAssertEqual(parse("https://www.youtube-nocookie.com/watch?v=dQw4w9WgXcQ")?.host, .youtube)
    }

    func test_invidious_watchShape() throws {
        let v = try XCTUnwrap(parse("https://yewtu.be/watch?v=dQw4w9WgXcQ"))
        XCTAssertEqual(v.host, .invidious)
        XCTAssertEqual(v.videoId, "dQw4w9WgXcQ")
        XCTAssertEqual(v.thumbnailURL?.absoluteString, "https://yewtu.be/vi/dQw4w9WgXcQ/hqdefault.jpg")
        // URLComponents percent-encodes the url= query value but the exact encoding of '?' vs '%3F'
        // is platform-defined; assert on components rather than the raw string.
        let oEmbed = try XCTUnwrap(v.oEmbedURL)
        XCTAssertEqual(oEmbed.host, "yewtu.be")
        XCTAssertEqual(oEmbed.path, "/oembed")
        let oEmbedComponents = try XCTUnwrap(URLComponents(url: oEmbed, resolvingAgainstBaseURL: false))
        let urlParam = try XCTUnwrap(oEmbedComponents.queryItems?.first { $0.name == "url" }?.value)
        XCTAssertEqual(urlParam, "https://yewtu.be/watch?v=dQw4w9WgXcQ")
        XCTAssertEqual(oEmbedComponents.queryItems?.first { $0.name == "format" }?.value, "json")
    }

    func test_peertube_wAndVideosWatch() throws {
        let short = try XCTUnwrap(parse("https://video.example/w/abc123XYZ"))
        XCTAssertEqual(short.host, .peertube)
        XCTAssertEqual(short.videoId, "abc123XYZ")
        XCTAssertNil(short.thumbnailURL, "PeerTube thumbnail comes from oEmbed, not derivable")
        XCTAssertEqual(short.oEmbedURL?.path, "/services/oembed")

        let long = try XCTUnwrap(parse("https://video.example/videos/watch/9c9de5e8-0a1e-484a-b099-e80766180a6d"))
        XCTAssertEqual(long.host, .peertube)
        XCTAssertEqual(long.videoId, "9c9de5e8-0a1e-484a-b099-e80766180a6d")
    }

    func test_negatives() {
        XCTAssertNil(parse("https://example.com/article"))
        XCTAssertNil(parse("https://example.com/image.jpg"))
        XCTAssertNil(parse("https://lemmy.world/c/games/p/1/slug"))
        XCTAssertNil(parse("https://example.com/watch?v=short")) // id too short for YT shape
        XCTAssertNil(parse("https://youtu.be/dQw4w9WgXcQ/extra")) // youtu.be id must be the sole segment
    }
}
