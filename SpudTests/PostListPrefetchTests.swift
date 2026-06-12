//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import Spud
@testable import SpudDataKit

/// Locks the thumbnail-URL derivation that drives feed image prefetching, so an
/// image post warms the cache ahead of scroll and a text/link post does not.
@MainActor
final class PostListPrefetchTests: XCTestCase {
    private let detector = PostContentDetectorService()

    private func row(url: String?, thumbnailUrl: String?) -> PostListRow {
        PostListRow(
            id: 1,
            serverPostId: 1,
            title: "t",
            body: nil,
            originalPostUrl: "https://example.test/post/1",
            url: url,
            thumbnailUrl: thumbnailUrl,
            urlEmbedTitle: nil,
            urlEmbedDescription: nil,
            communityName: "c",
            communityActorId: nil,
            serverCommunityId: 1,
            creatorPersonId: 1,
            score: 0,
            numberOfComments: 0,
            voteStatus: nil,
            isRead: false,
            isSaved: false,
            isRemoved: false,
            isLocked: false,
            isFeaturedCommunity: false,
            isFeaturedLocal: false,
            isDeleted: false,
            published: Date(timeIntervalSince1970: 0)
        )
    }

    func test_imagePost_prefetchesTheImageUrl() {
        let url = PostListPostViewModel.prefetchThumbnailUrl(
            for: row(url: "https://example.test/cat.jpg", thumbnailUrl: nil),
            postContentDetector: detector
        )
        XCTAssertEqual(url?.absoluteString, "https://example.test/cat.jpg")
    }

    func test_imagePost_prefersThumbnailWhenPresent() {
        let url = PostListPostViewModel.prefetchThumbnailUrl(
            for: row(
                url: "https://example.test/cat.png",
                thumbnailUrl: "https://example.test/cat_thumb.png"
            ),
            postContentDetector: detector
        )
        XCTAssertEqual(url?.absoluteString, "https://example.test/cat_thumb.png")
    }

    func test_externalLinkPost_hasNothingToPrefetch() {
        let url = PostListPostViewModel.prefetchThumbnailUrl(
            for: row(url: "https://example.test/article", thumbnailUrl: nil),
            postContentDetector: detector
        )
        XCTAssertNil(url)
    }

    func test_textPost_hasNothingToPrefetch() {
        let url = PostListPostViewModel.prefetchThumbnailUrl(
            for: row(url: nil, thumbnailUrl: nil),
            postContentDetector: detector
        )
        XCTAssertNil(url)
    }
}
