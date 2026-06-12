//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import SpudDataKit

final class PostContentDetectorTests: XCTestCase {
    private let detector = PostContentDetectorService()

    private func contentType(url: String?, thumbnailUrl: String? = nil) -> PostContentType {
        detector.contentTypeForUrl(
            url: url.flatMap { URL(string: $0) },
            thumbnailUrl: thumbnailUrl.flatMap { URL(string: $0) },
            embedTitle: nil,
            embedDescription: nil
        )
    }

    func test_nilUrl_isTextOrEmpty() {
        XCTAssertEqual(contentType(url: nil), .textOrEmpty)
    }

    func test_imageExtensions_areDetectedAsStillImages() {
        for ext in ["jpg", "jpeg", "png", "webp"] {
            let type = contentType(url: "https://example.test/pic.\(ext)")
            guard case let .image(image) = type else {
                return XCTFail("\(ext) should be an image, got \(type)")
            }
            XCTAssertFalse(image.isAnimated, "\(ext) is not animated")
        }
    }

    func test_gif_isDetectedAsAnimatedImage() {
        let type = contentType(url: "https://example.test/funny.gif")
        guard case let .image(image) = type else {
            return XCTFail("gif should be an image, got \(type)")
        }
        XCTAssertTrue(image.isAnimated, "gif should be flagged animated")
    }

    func test_nonImageUrl_isExternalLink() {
        let type = contentType(url: "https://example.test/article")
        guard case .externalLink = type else {
            return XCTFail("a non-image url should be an external link, got \(type)")
        }
    }

    func test_playableVideoExtensions_areDetectedAsVideo() {
        for ext in ["mp4", "mov", "m4v"] {
            let type = contentType(url: "https://example.test/clip.\(ext)")
            guard case let .video(video) = type else {
                return XCTFail("\(ext) should be a video, got \(type)")
            }
            XCTAssertEqual(video.videoUrl.absoluteString, "https://example.test/clip.\(ext)")
        }
    }

    func test_webm_isNotVideo_soItOpensExternally() {
        // AVFoundation can't decode webm; it must stay an external link rather
        // than route to a dead player.
        let type = contentType(url: "https://example.test/clip.webm")
        guard case .externalLink = type else {
            return XCTFail("webm should be an external link, got \(type)")
        }
    }

    func test_videoPost_carriesPosterThumbnail() {
        let type = contentType(
            url: "https://example.test/clip.mp4",
            thumbnailUrl: "https://example.test/poster.jpg"
        )
        guard case let .video(video) = type else {
            return XCTFail("expected video, got \(type)")
        }
        XCTAssertEqual(video.thumbnailUrl?.absoluteString, "https://example.test/poster.jpg")
    }

    func test_imageUrl_carriesThumbnailAndFullUrls() {
        let type = contentType(
            url: "https://example.test/full.png",
            thumbnailUrl: "https://example.test/thumb.png"
        )
        guard case let .image(image) = type else {
            return XCTFail("expected image, got \(type)")
        }
        XCTAssertEqual(image.imageUrl.absoluteString, "https://example.test/full.png")
        XCTAssertEqual(image.thumbnailUrl?.absoluteString, "https://example.test/thumb.png")
    }
}
