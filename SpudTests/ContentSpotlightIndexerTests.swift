//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudUtilKit
import XCTest
@testable import Spud
@testable import SpudDataKit

final class ContentSpotlightIndexerTests: XCTestCase {
    func test_makeItem_buildsRoutingIdentifierAndTitle() throws {
        let row = IndexableContentRow(
            serverPostId: 5,
            title: "Hello world",
            originalPostUrl: "https://lemmy.world/post/5",
            thumbnailUrl: "https://lemmy.world/pic.jpg",
            communityName: "programming"
        )
        let item = try XCTUnwrap(ContentSpotlightIndexer.makeItem(from: row))

        let expected = try URL.SpudInternalLink.objectAtURL(url: XCTUnwrap(URL(string: "https://lemmy.world/post/5"))).url.absoluteString
        XCTAssertEqual(item.uniqueIdentifier, expected)
        XCTAssertEqual(item.domainIdentifier, "content")
        XCTAssertEqual(item.attributeSet.title, "Hello world")
        XCTAssertEqual(item.attributeSet.thumbnailURL, URL(string: "https://lemmy.world/pic.jpg"))
        XCTAssertEqual(item.attributeSet.contentDescription, "!programming")
    }

    func test_makeItem_returnsNilWhenNoCanonicalURL() {
        let row = IndexableContentRow(
            serverPostId: 5,
            title: "No URL",
            originalPostUrl: nil,
            thumbnailUrl: nil,
            communityName: nil
        )
        XCTAssertNil(ContentSpotlightIndexer.makeItem(from: row))
    }
}
