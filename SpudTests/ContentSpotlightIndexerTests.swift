//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit
import Testing
@testable import Spud
@testable import SpudDataKit

struct ContentSpotlightIndexerTests {
    @Test
    func makeItem_buildsRoutingIdentifierAndTitle() throws {
        let row = IndexableContentRow(
            serverPostId: 5,
            title: "Hello world",
            originalPostUrl: "https://lemmy.world/post/5",
            thumbnailUrl: "https://lemmy.world/pic.jpg",
            communityName: "programming",
            isNsfw: false
        )
        let item = try #require(ContentSpotlightIndexer.makeItem(from: row))

        let expected = try URL.SpudInternalLink.objectAtURL(url: #require(URL(string: "https://lemmy.world/post/5"))).url.absoluteString
        #expect(item.uniqueIdentifier == expected)
        #expect(item.domainIdentifier == "content")
        #expect(item.attributeSet.title == "Hello world")
        #expect(item.attributeSet.thumbnailURL == URL(string: "https://lemmy.world/pic.jpg"))
        #expect(item.attributeSet.contentDescription == "!programming")
    }

    @Test
    func makeItem_returnsNilWhenNoCanonicalURL() {
        let row = IndexableContentRow(
            serverPostId: 5,
            title: "No URL",
            originalPostUrl: nil,
            thumbnailUrl: nil,
            communityName: nil,
            isNsfw: false
        )
        #expect(ContentSpotlightIndexer.makeItem(from: row) == nil)
    }

    @Test
    func makeItem_returnsNilForNsfw() {
        let row = IndexableContentRow(
            serverPostId: 5,
            title: "Hello world",
            originalPostUrl: "https://lemmy.world/post/5",
            thumbnailUrl: nil,
            communityName: "programming",
            isNsfw: true
        )
        #expect(ContentSpotlightIndexer.makeItem(from: row) == nil)
    }
}
