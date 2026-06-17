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
            altText: nil,
            communityName: "c",
            communityActorId: nil,
            serverCommunityId: 1,
            creatorPersonId: 1,
            creatorName: nil,
            creatorActorId: nil,
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

    func test_externalLinkWithEmbedThumbnail_prefetchesTheThumbnail() {
        let url = PostListPostViewModel.prefetchThumbnailUrl(
            for: row(
                url: "https://example.test/article",
                thumbnailUrl: "https://example.test/embed.jpg"
            ),
            postContentDetector: detector
        )
        XCTAssertEqual(url?.absoluteString, "https://example.test/embed.jpg")
    }

    // MARK: thumbnail kind

    func test_thumbnail_imagePost_isImage() throws {
        let (thumbnail, fullImageUrl) = PostListPostViewModel.thumbnail(
            for: row(url: "https://example.test/cat.jpg", thumbnailUrl: nil),
            postContentDetector: detector
        )
        XCTAssertEqual(thumbnail, try .image(thumbnailUrl: XCTUnwrap(URL(string: "https://example.test/cat.jpg"))))
        XCTAssertEqual(fullImageUrl?.absoluteString, "https://example.test/cat.jpg")
    }

    func test_thumbnail_externalLinkWithEmbed_isLinkImage_andHasNoFullImage() throws {
        let (thumbnail, fullImageUrl) = PostListPostViewModel.thumbnail(
            for: row(
                url: "https://example.test/article",
                thumbnailUrl: "https://example.test/embed.jpg"
            ),
            postContentDetector: detector
        )
        XCTAssertEqual(thumbnail, try .linkImage(
            thumbnailUrl: XCTUnwrap(URL(string: "https://example.test/embed.jpg")),
            linkUrl: XCTUnwrap(URL(string: "https://example.test/article"))
        ))
        XCTAssertNil(fullImageUrl, "a link preview does not open the image viewer")
    }

    func test_thumbnail_externalLinkWithoutEmbed_isLink_andHasNoFullImage() throws {
        let (thumbnail, fullImageUrl) = PostListPostViewModel.thumbnail(
            for: row(url: "https://example.test/article", thumbnailUrl: nil),
            postContentDetector: detector
        )
        XCTAssertEqual(thumbnail, try .link(linkUrl: XCTUnwrap(URL(string: "https://example.test/article"))))
        XCTAssertNil(fullImageUrl, "a link post does not open the image viewer")
    }

    func test_thumbnail_textPost_isText() {
        let (thumbnail, fullImageUrl) = PostListPostViewModel.thumbnail(
            for: row(url: nil, thumbnailUrl: nil),
            postContentDetector: detector
        )
        XCTAssertEqual(thumbnail, .text)
        XCTAssertNil(fullImageUrl)
    }

    func test_thumbnail_videoPost_isVideo_withPosterAndNoFullImage() throws {
        let (thumbnail, fullImageUrl) = PostListPostViewModel.thumbnail(
            for: row(
                url: "https://example.test/clip.mp4",
                thumbnailUrl: "https://example.test/poster.jpg"
            ),
            postContentDetector: detector
        )
        XCTAssertEqual(thumbnail, try .video(
            posterUrl: XCTUnwrap(URL(string: "https://example.test/poster.jpg")),
            videoUrl: XCTUnwrap(URL(string: "https://example.test/clip.mp4"))
        ))
        XCTAssertNil(fullImageUrl, "video posts do not open the image viewer")
    }

    func test_videoPost_prefetchesThePoster() {
        let url = PostListPostViewModel.prefetchThumbnailUrl(
            for: row(
                url: "https://example.test/clip.mp4",
                thumbnailUrl: "https://example.test/poster.jpg"
            ),
            postContentDetector: detector
        )
        XCTAssertEqual(url?.absoluteString, "https://example.test/poster.jpg")
    }
}
