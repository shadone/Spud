//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import Spud
@testable import SpudDataKit

/// Locks the thumbnail-URL derivation that drives feed image prefetching, so an
/// image post warms the cache ahead of scroll and a text/link post does not.
@MainActor
struct PostListPrefetchTests {
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
            isNsfw: false,
            published: Date(timeIntervalSince1970: 0)
        )
    }

    @Test
    func imagePost_prefetchesTheImageUrl() {
        let url = PostListPostViewModel.prefetchThumbnailUrl(
            for: row(url: "https://example.test/cat.jpg", thumbnailUrl: nil),
            postContentDetector: detector
        )
        #expect(url?.absoluteString == "https://example.test/cat.jpg")
    }

    @Test
    func imagePost_prefersThumbnailWhenPresent() {
        let url = PostListPostViewModel.prefetchThumbnailUrl(
            for: row(
                url: "https://example.test/cat.png",
                thumbnailUrl: "https://example.test/cat_thumb.png"
            ),
            postContentDetector: detector
        )
        #expect(url?.absoluteString == "https://example.test/cat_thumb.png")
    }

    @Test
    func externalLinkPost_hasNothingToPrefetch() {
        let url = PostListPostViewModel.prefetchThumbnailUrl(
            for: row(url: "https://example.test/article", thumbnailUrl: nil),
            postContentDetector: detector
        )
        #expect(url == nil)
    }

    @Test
    func textPost_hasNothingToPrefetch() {
        let url = PostListPostViewModel.prefetchThumbnailUrl(
            for: row(url: nil, thumbnailUrl: nil),
            postContentDetector: detector
        )
        #expect(url == nil)
    }

    @Test
    func externalLinkWithEmbedThumbnail_prefetchesTheThumbnail() {
        let url = PostListPostViewModel.prefetchThumbnailUrl(
            for: row(
                url: "https://example.test/article",
                thumbnailUrl: "https://example.test/embed.jpg"
            ),
            postContentDetector: detector
        )
        #expect(url?.absoluteString == "https://example.test/embed.jpg")
    }

    // MARK: thumbnail kind

    @Test
    func thumbnail_imagePost_isImage() throws {
        let (thumbnail, fullImageUrl) = PostListPostViewModel.thumbnail(
            for: row(url: "https://example.test/cat.jpg", thumbnailUrl: nil),
            postContentDetector: detector
        )
        #expect(try thumbnail == .image(thumbnailUrl: #require(URL(string: "https://example.test/cat.jpg"))))
        #expect(fullImageUrl?.absoluteString == "https://example.test/cat.jpg")
    }

    @Test
    func thumbnail_externalLinkWithEmbed_isLinkImage_andHasNoFullImage() throws {
        let (thumbnail, fullImageUrl) = PostListPostViewModel.thumbnail(
            for: row(
                url: "https://example.test/article",
                thumbnailUrl: "https://example.test/embed.jpg"
            ),
            postContentDetector: detector
        )
        #expect(try thumbnail == .linkImage(
            thumbnailUrl: #require(URL(string: "https://example.test/embed.jpg")),
            linkUrl: #require(URL(string: "https://example.test/article"))
        ))
        #expect(fullImageUrl == nil, "a link preview does not open the image viewer")
    }

    @Test
    func thumbnail_externalLinkWithoutEmbed_isLink_andHasNoFullImage() throws {
        let (thumbnail, fullImageUrl) = PostListPostViewModel.thumbnail(
            for: row(url: "https://example.test/article", thumbnailUrl: nil),
            postContentDetector: detector
        )
        #expect(try thumbnail == .link(linkUrl: #require(URL(string: "https://example.test/article"))))
        #expect(fullImageUrl == nil, "a link post does not open the image viewer")
    }

    @Test
    func thumbnail_textPost_isText() {
        let (thumbnail, fullImageUrl) = PostListPostViewModel.thumbnail(
            for: row(url: nil, thumbnailUrl: nil),
            postContentDetector: detector
        )
        #expect(thumbnail == .text)
        #expect(fullImageUrl == nil)
    }

    @Test
    func thumbnail_videoPost_isVideo_withPosterAndNoFullImage() throws {
        let (thumbnail, fullImageUrl) = PostListPostViewModel.thumbnail(
            for: row(
                url: "https://example.test/clip.mp4",
                thumbnailUrl: "https://example.test/poster.jpg"
            ),
            postContentDetector: detector
        )
        #expect(try thumbnail == .video(
            posterUrl: #require(URL(string: "https://example.test/poster.jpg")),
            videoUrl: #require(URL(string: "https://example.test/clip.mp4"))
        ))
        #expect(fullImageUrl == nil, "video posts do not open the image viewer")
    }

    @Test
    func videoPost_prefetchesThePoster() {
        let url = PostListPostViewModel.prefetchThumbnailUrl(
            for: row(
                url: "https://example.test/clip.mp4",
                thumbnailUrl: "https://example.test/poster.jpg"
            ),
            postContentDetector: detector
        )
        #expect(url?.absoluteString == "https://example.test/poster.jpg")
    }
}
