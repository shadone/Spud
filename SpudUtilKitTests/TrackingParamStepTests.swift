//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import XCTest
@testable import SpudUtilKit

final class TrackingParamStepTests: XCTestCase {
    private func stripped(_ string: String) -> String? {
        guard let url = URL(string: string) else { return nil }
        return TrackingParamStep().apply(url, config: .default).absoluteString
    }

    func test_stripsUTMWildcardAndKnownTrackers_keepsOthers() {
        XCTAssertEqual(
            stripped("https://example.com/p?utm_source=a&utm_medium=b&id=42&fbclid=xyz&gclid=q"),
            "https://example.com/p?id=42"
        )
    }

    func test_removesQueryEntirelyWhenOnlyTrackers() {
        XCTAssertEqual(stripped("https://example.com/p?utm_source=a"), "https://example.com/p")
    }

    func test_leavesURLWithoutQueryUnchanged() {
        XCTAssertEqual(stripped("https://example.com/p"), "https://example.com/p")
    }

    func test_isCaseInsensitiveOnParamNames() {
        XCTAssertEqual(stripped("https://example.com/p?UTM_Source=a&Keep=1"), "https://example.com/p?Keep=1")
    }

    func test_youtubePreservesTimestampAndVideoIdButStripsSiFeaturePp() {
        XCTAssertEqual(
            stripped("https://youtu.be/dQw4w9WgXcQ?si=track&t=42"),
            "https://youtu.be/dQw4w9WgXcQ?t=42"
        )
        XCTAssertEqual(
            stripped("https://www.youtube.com/watch?v=dQw4w9WgXcQ&feature=share&pp=abc&t=10"),
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=10"
        )
    }

    func test_spotifyStripsSi() {
        XCTAssertEqual(
            stripped("https://open.spotify.com/track/abc?si=track123"),
            "https://open.spotify.com/track/abc"
        )
    }

    func test_amazonFlattensToDpAsin() {
        XCTAssertEqual(
            stripped("https://www.amazon.com/Some-Product-Name/dp/B08N5WRWNW/ref=sr_1_1?keywords=x&tag=y"),
            "https://www.amazon.com/dp/B08N5WRWNW"
        )
    }

    func test_amazonGpProductForm() {
        XCTAssertEqual(
            stripped("https://amazon.co.uk/gp/product/B08N5WRWNW?psc=1&tag=z"),
            "https://amazon.co.uk/gp/product/B08N5WRWNW"
        )
    }

    func test_amazonWithoutAsinStillStripsGlobalTrackers() {
        XCTAssertEqual(
            stripped("https://www.amazon.com/gp/bestsellers?utm_source=a&node=1"),
            "https://www.amazon.com/gp/bestsellers?node=1"
        )
    }

    func test_doesNotStripWhenDisabled() throws {
        var config = URLSanitizerConfig.default
        config.stripTrackingParams = false
        let url = try XCTUnwrap(URL(string: "https://example.com/p?utm_source=a&id=42"))
        XCTAssertEqual(TrackingParamStep().apply(url, config: config).absoluteString, "https://example.com/p?utm_source=a&id=42")
    }
}
