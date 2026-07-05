//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudDataKit

struct PostContentDetectorTests {
    private let detector = PostContentDetectorService()

    private func contentType(url: String?, thumbnailUrl: String? = nil) -> PostContentType {
        detector.contentTypeForUrl(
            url: url.flatMap { URL(string: $0) },
            thumbnailUrl: thumbnailUrl.flatMap { URL(string: $0) },
            embedTitle: nil,
            embedDescription: nil
        )
    }

    @Test
    func nilUrl_isTextOrEmpty() {
        #expect(contentType(url: nil) == .textOrEmpty)
    }

    @Test
    func imageExtensions_areDetectedAsStillImages() {
        for ext in ["jpg", "jpeg", "png", "webp", "avif"] {
            let type = contentType(url: "https://example.test/pic.\(ext)")
            guard case let .image(image) = type else {
                Issue.record("\(ext) should be an image, got \(type)")
                return
            }
            #expect(!(image.isAnimated), "\(ext) is not animated")
        }
    }

    @Test
    func gif_isDetectedAsAnimatedImage() {
        let type = contentType(url: "https://example.test/funny.gif")
        guard case let .image(image) = type else {
            Issue.record("gif should be an image, got \(type)")
            return
        }
        #expect(image.isAnimated, "gif should be flagged animated")
    }

    @Test
    func avifPost_isDetectedAsStillImage() {
        // pict-rs on some instances (e.g. lemmy.zip) transcodes uploads to AVIF,
        // so the post url ends in .avif. iOS decodes AVIF natively, so it must
        // render inline as an image instead of falling through to an external
        // link. Real-world case: lemmy.zip/post/65731968.
        let type = contentType(url: "https://lemmy.zip/pictrs/image/717b5470-fd41-4aba-b0b3-8b7620003bfc.avif")
        guard case let .image(image) = type else {
            Issue.record("an avif url should be an image, got \(type)")
            return
        }
        #expect(!(image.isAnimated), "avif is treated as a still image")
    }

    @Test
    func nonImageUrl_isExternalLink() {
        let type = contentType(url: "https://example.test/article")
        guard case .externalLink = type else {
            Issue.record("a non-image url should be an external link, got \(type)")
            return
        }
    }

    @Test
    func playableVideoExtensions_areDetectedAsVideo() {
        for ext in ["mp4", "mov", "m4v"] {
            let type = contentType(url: "https://example.test/clip.\(ext)")
            guard case let .video(video) = type else {
                Issue.record("\(ext) should be a video, got \(type)")
                return
            }
            #expect(video.videoUrl.absoluteString == "https://example.test/clip.\(ext)")
        }
    }

    @Test
    func webm_isNotVideo_soItOpensExternally() {
        // AVFoundation can't decode webm; it must stay an external link rather
        // than route to a dead player.
        let type = contentType(url: "https://example.test/clip.webm")
        guard case .externalLink = type else {
            Issue.record("webm should be an external link, got \(type)")
            return
        }
    }

    @Test
    func videoPost_carriesPosterThumbnail() {
        let type = contentType(
            url: "https://example.test/clip.mp4",
            thumbnailUrl: "https://example.test/poster.jpg"
        )
        guard case let .video(video) = type else {
            Issue.record("expected video, got \(type)")
            return
        }
        #expect(video.thumbnailUrl?.absoluteString == "https://example.test/poster.jpg")
    }

    @Test
    func imageUrl_carriesThumbnailAndFullUrls() {
        let type = contentType(
            url: "https://example.test/full.png",
            thumbnailUrl: "https://example.test/thumb.png"
        )
        guard case let .image(image) = type else {
            Issue.record("expected image, got \(type)")
            return
        }
        #expect(image.imageUrl.absoluteString == "https://example.test/full.png")
        #expect(image.thumbnailUrl?.absoluteString == "https://example.test/thumb.png")
    }

    @Test
    func lemmyImageProxyUrl_isDetectedAsImage() {
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
            Issue.record("a proxied image url should be an image, got \(type)")
            return
        }
        #expect(!(image.isAnimated))
        // The proxy url stays the image url so it loads through the instance's
        // proxy; ImageService's plain User-Agent keeps the proxy host from 403ing.
        #expect(image.imageUrl.absoluteString == proxyUrl)
        #expect(image.thumbnailUrl?.absoluteString == "https://discuss.tchncs.de/pictrs/image/thumb.png")
    }

    @Test
    func lemmyImageProxyGifUrl_isDetectedAsAnimatedImage() {
        let proxyUrl = "https://lemmy.ml/api/v3/image_proxy?url=https%3A%2F%2Ffeddit.nl%2Fpictrs%2Fimage%2Ffunny.gif"
        let type = contentType(url: proxyUrl)
        guard case let .image(image) = type else {
            Issue.record("a proxied gif should be an image, got \(type)")
            return
        }
        #expect(image.isAnimated, "proxied gif should be flagged animated")
    }

    @Test
    func imageProxyWrappingNonImage_staysExternalLink() {
        // image_proxy only ever wraps images in practice, but if the embedded url
        // has no image extension we must not misclassify it as an image.
        let type = contentType(url: "https://lemmy.ml/api/v3/image_proxy?url=https%3A%2F%2Fexample.test%2Farticle")
        guard case .externalLink = type else {
            Issue.record("proxy wrapping a non-image should be an external link, got \(type)")
            return
        }
    }

    @Test
    func streamableUrl_isDetectedAsVideo() {
        let type = contentType(url: "https://streamable.com/67295820")
        guard case let .video(video) = type else {
            Issue.record("streamable should be a video, got \(type)")
            return
        }
        #expect(video.videoUrl.absoluteString == "https://streamable.com/67295820")
    }

    @Test
    func streamableUrl_usesServerThumbnailAsPoster() {
        let type = contentType(
            url: "https://streamable.com/67295820",
            thumbnailUrl: "https://server.example/thumb.jpg"
        )
        guard case let .video(video) = type else {
            Issue.record("streamable should be a video, got \(type)")
            return
        }
        #expect(video.thumbnailUrl?.absoluteString == "https://server.example/thumb.jpg")
    }

    @Test
    func peerTubeUrl_isDetectedAsVideo() {
        let url = "https://tube.example/videos/watch/0e3c8d2a-1234-4abc-9def-0123456789ab"
        let type = contentType(url: url)
        guard case let .video(video) = type else {
            Issue.record("PeerTube URL should be a video, got \(type)")
            return
        }
        #expect(video.videoUrl.absoluteString == url)
    }

    @Test
    func youTubeUrl_isDetectedAsVideo() {
        let url = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        let type = contentType(url: url)
        guard case let .video(video) = type else {
            Issue.record("YouTube URL should be a video, got \(type)")
            return
        }
        #expect(video.videoUrl.absoluteString == url)
    }

    @Test
    func unrecognizedLink_staysExternalLink() {
        let type = contentType(url: "https://example.com/some/article")
        guard case .externalLink = type else {
            Issue.record("unrecognized link should be externalLink, got \(type)")
            return
        }
    }
}
