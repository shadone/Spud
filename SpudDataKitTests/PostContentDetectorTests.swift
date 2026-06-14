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
        for ext in ["jpg", "jpeg", "png", "webp", "avif"] {
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

    func test_avifPost_isDetectedAsStillImage() {
        // pict-rs on some instances (e.g. lemmy.zip) transcodes uploads to AVIF,
        // so the post url ends in .avif. iOS decodes AVIF natively, so it must
        // render inline as an image instead of falling through to an external
        // link. Real-world case: lemmy.zip/post/65731968.
        let type = contentType(url: "https://lemmy.zip/pictrs/image/717b5470-fd41-4aba-b0b3-8b7620003bfc.avif")
        guard case let .image(image) = type else {
            return XCTFail("an avif url should be an image, got \(type)")
        }
        XCTAssertFalse(image.isAnimated, "avif is treated as a still image")
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

    func test_lemmyImageProxyUrl_isDetectedAsImage() {
        // Instances with image_proxy enabled wrap the real image url in a proxy
        // endpoint whose path has no extension; the .png lives in the query.
        // This is the exact url shape from feddit.nl/post/54717157 as served by a
        // proxying home instance, which previously rendered as a link.
        let proxyUrl = "https://lemmy.ml/api/v3/image_proxy?url=https%3A%2F%2Ffeddit.nl%2Fpictrs%2Fimage%2F5fbd8b47-33bd-45bc-9f6d-df5473ca84f0.png"
        let type = contentType(
            url: proxyUrl,
            thumbnailUrl: "https://discuss.tchncs.de/pictrs/image/thumb.png"
        )
        guard case let .image(image) = type else {
            return XCTFail("a proxied image url should be an image, got \(type)")
        }
        XCTAssertFalse(image.isAnimated)
        // The proxy url stays the image url so it loads through the instance's
        // proxy; ImageService's plain User-Agent keeps the proxy host from 403ing.
        XCTAssertEqual(image.imageUrl.absoluteString, proxyUrl)
        XCTAssertEqual(image.thumbnailUrl?.absoluteString, "https://discuss.tchncs.de/pictrs/image/thumb.png")
    }

    func test_lemmyImageProxyGifUrl_isDetectedAsAnimatedImage() {
        let proxyUrl = "https://lemmy.ml/api/v3/image_proxy?url=https%3A%2F%2Ffeddit.nl%2Fpictrs%2Fimage%2Ffunny.gif"
        let type = contentType(url: proxyUrl)
        guard case let .image(image) = type else {
            return XCTFail("a proxied gif should be an image, got \(type)")
        }
        XCTAssertTrue(image.isAnimated, "proxied gif should be flagged animated")
    }

    func test_imageProxyWrappingNonImage_staysExternalLink() {
        // image_proxy only ever wraps images in practice, but if the embedded url
        // has no image extension we must not misclassify it as an image.
        let type = contentType(url: "https://lemmy.ml/api/v3/image_proxy?url=https%3A%2F%2Fexample.test%2Farticle")
        guard case .externalLink = type else {
            return XCTFail("proxy wrapping a non-image should be an external link, got \(type)")
        }
    }
}
