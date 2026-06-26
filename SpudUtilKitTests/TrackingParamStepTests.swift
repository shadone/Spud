//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudUtilKit

struct TrackingParamStepTests {
    private func stripped(_ string: String) -> String? {
        guard let url = URL(string: string) else { return nil }
        return TrackingParamStep().apply(url, config: .default).absoluteString
    }

    @Test
    func stripsUTMWildcardAndKnownTrackers_keepsOthers() {
        #expect(
            stripped("https://example.com/p?utm_source=a&utm_medium=b&id=42&fbclid=xyz&gclid=q") ==
                "https://example.com/p?id=42"
        )
    }

    @Test
    func removesQueryEntirelyWhenOnlyTrackers() {
        #expect(stripped("https://example.com/p?utm_source=a") == "https://example.com/p")
    }

    @Test
    func leavesURLWithoutQueryUnchanged() {
        #expect(stripped("https://example.com/p") == "https://example.com/p")
    }

    @Test
    func isCaseInsensitiveOnParamNames() {
        #expect(stripped("https://example.com/p?UTM_Source=a&Keep=1") == "https://example.com/p?Keep=1")
    }

    @Test
    func youtubePreservesTimestampAndVideoIdButStripsSiFeaturePp() {
        #expect(
            stripped("https://youtu.be/dQw4w9WgXcQ?si=track&t=42") ==
                "https://youtu.be/dQw4w9WgXcQ?t=42"
        )
        #expect(
            stripped("https://www.youtube.com/watch?v=dQw4w9WgXcQ&feature=share&pp=abc&t=10") ==
                "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=10"
        )
    }

    @Test
    func spotifyStripsSi() {
        #expect(
            stripped("https://open.spotify.com/track/abc?si=track123") ==
                "https://open.spotify.com/track/abc"
        )
    }

    @Test
    func amazonFlattensToDpAsin() {
        #expect(
            stripped("https://www.amazon.com/Some-Product-Name/dp/B08N5WRWNW/ref=sr_1_1?keywords=x&tag=y") ==
                "https://www.amazon.com/dp/B08N5WRWNW"
        )
    }

    @Test
    func amazonGpProductForm() {
        #expect(
            stripped("https://amazon.co.uk/gp/product/B08N5WRWNW?psc=1&tag=z") ==
                "https://amazon.co.uk/gp/product/B08N5WRWNW"
        )
    }

    @Test
    func amazonWithoutAsinStillStripsGlobalTrackers() {
        #expect(
            stripped("https://www.amazon.com/gp/bestsellers?utm_source=a&node=1") ==
                "https://www.amazon.com/gp/bestsellers?node=1"
        )
    }

    @Test
    func doesNotStripWhenDisabled() throws {
        var config = URLSanitizerConfig.default
        config.stripTrackingParams = false
        let url = try #require(URL(string: "https://example.com/p?utm_source=a&id=42"))
        #expect(TrackingParamStep().apply(url, config: config).absoluteString == "https://example.com/p?utm_source=a&id=42")
    }
}
