//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudUtilKit

struct YouTubeReferenceTests {
    private func ref(_ s: String) -> YouTubeReference? {
        YouTubeReference.extract(from: URL(string: s)!)
    }

    @Test
    func youtubeWatchEmbedShortsLiveV() {
        #expect(ref("https://www.youtube.com/watch?v=dQw4w9WgXcQ")?.sourceKind == .youtube)
        #expect(ref("https://m.youtube.com/watch?v=dQw4w9WgXcQ")?.videoId == "dQw4w9WgXcQ")
        #expect(ref("https://www.youtube.com/embed/dQw4w9WgXcQ")?.videoId == "dQw4w9WgXcQ")
        #expect(ref("https://www.youtube.com/shorts/dQw4w9WgXcQ")?.videoId == "dQw4w9WgXcQ")
        #expect(ref("https://www.youtube.com/live/dQw4w9WgXcQ")?.videoId == "dQw4w9WgXcQ")
        #expect(ref("https://www.youtube.com/v/dQw4w9WgXcQ")?.videoId == "dQw4w9WgXcQ")
        #expect(ref("https://youtu.be/dQw4w9WgXcQ")?.sourceKind == .youtube)
    }

    @Test
    func redirectInvidiousIsYoutube() {
        #expect(ref("https://redirect.invidious.io/watch?v=dQw4w9WgXcQ")?.sourceKind == .youtube)
        #expect(ref("https://redirect.invidious.io/embed/dQw4w9WgXcQ")?.videoId == "dQw4w9WgXcQ")
    }

    @Test
    func catalogFrontEnds() throws {
        let inv = try #require(ref("https://yewtu.be/watch?v=dQw4w9WgXcQ"))
        #expect(inv.sourceKind == .frontEnd(.invidious))
        #expect(inv.sourceHost == "yewtu.be")
        let piped = try #require(ref("https://piped.video/watch?v=dQw4w9WgXcQ"))
        #expect(piped.sourceKind == .frontEnd(.piped))
        #expect(piped.videoId == "dQw4w9WgXcQ")
    }

    @Test
    func unknownHostFallsBackToShape() {
        #expect(ref("https://some.random.host/watch?v=dQw4w9WgXcQ")?.sourceKind == .frontEndShape)
    }

    @Test
    func timestampParsedFromQueryAndFragment() {
        #expect(ref("https://youtu.be/dQw4w9WgXcQ?t=90")?.timestampSeconds == 90)
        #expect(ref("https://www.youtube.com/watch?v=dQw4w9WgXcQ&start=42")?.timestampSeconds == 42)
        #expect(ref("https://www.youtube.com/watch?v=dQw4w9WgXcQ#t=7")?.timestampSeconds == 7)
        #expect(ref("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=1m30s")?.timestampSeconds == nil) // richer forms omitted in v1
        #expect(ref("https://youtu.be/dQw4w9WgXcQ")?.timestampSeconds == nil)
    }

    @Test
    func negatives() {
        #expect(ref("https://example.com/article") == nil)
        #expect(ref("https://www.youtube.com/watch?v=short") == nil) // id must be 11 chars
        #expect(ref("https://youtu.be/dQw4w9WgXcQ/extra") == nil) // id must be sole segment
        #expect(ref("https://www.youtube.com/results?search_query=cats") == nil) // non-video path
        #expect(ref("ftp://youtu.be/dQw4w9WgXcQ") == nil) // non-http scheme
    }

    @Test
    func catalogLookupStripsWwwAndM() {
        #expect(YouTubeFrontEndCatalog.instance(forHost: "yewtu.be")?.kind == .invidious)
        #expect(YouTubeFrontEndCatalog.instance(forHost: "piped.video")?.kind == .piped)
        #expect(YouTubeFrontEndCatalog.instance(forHost: "piped.video")?.apiHost != nil)
        #expect(YouTubeFrontEndCatalog.instance(forHost: "unknown.example") == nil)
    }
}
