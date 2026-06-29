//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Nuke
import Testing
import UIKit
@testable import SpudDataKit

struct ImageServiceFullFetchTests {
    @Test
    func fullFetch_yieldsReadyImage() async throws {
        let url = try #require(URL(string: "https://example.com/full.png"))
        let pipeline = ImagePipeline { config in
            config.dataLoader = StubDataLoader(
                result: .success((ImageFixture.pngData(), ImageFixture.httpResponse(url)))
            )
            config.imageCache = nil
        }
        let service = ImageService(alertService: AlertService(), pipeline: pipeline)

        var lastImage: UIImage?
        for await state in service.fetch(url, thumbnail: nil) {
            if case let .ready(image) = state { lastImage = image }
        }
        #expect(lastImage != nil)
    }

    @Test
    func fullFetch_seedsThumbnailFromMemoryCache() async throws {
        let fullUrl = try #require(URL(string: "https://example.com/full.png"))
        let thumbUrl = try #require(URL(string: "https://example.com/thumb.png"))

        let memoryCache = ImageCache()
        let pipeline = ImagePipeline { config in
            config.dataLoader = StubDataLoader(
                result: .success((ImageFixture.pngData(), ImageFixture.httpResponse(fullUrl)))
            )
            config.imageCache = memoryCache
        }
        // Pre-populate the thumbnail in the memory cache.
        pipeline.cache[ImageRequest(url: thumbUrl)] = ImageContainer(image: ImageFixture.image())

        let service = ImageService(alertService: AlertService(), pipeline: pipeline)

        var loadingThumbnail: UIImage?
        for await state in service.fetch(fullUrl, thumbnail: thumbUrl) {
            if case let .loading(thumbnail) = state { loadingThumbnail = thumbnail }
        }
        #expect(loadingThumbnail != nil, "Expected .loading to be seeded with the cached thumbnail image")
    }

    @Test
    func fullFetch_seedsThumbnailFromDownsampledCacheKey() async throws {
        // Regression: the feed cell and the offline downloader warm a thumbnail
        // under the DOWNSAMPLED request key (a `Resize` processor at the feed
        // thumbnail size), not the bare url key. Before the fix, the post-detail
        // header's `fetch(_:thumbnail:)` probed only the bare key and missed the
        // list's cached thumbnail — so it showed a gray spinner box (or, offline,
        // the hard failure plate) even though the decoded thumbnail was cached.
        let fullUrl = try #require(URL(string: "https://example.com/full.png"))
        let thumbUrl = try #require(URL(string: "https://example.com/thumb.png"))

        let memoryCache = ImageCache()
        let pipeline = ImagePipeline { config in
            // Full image never loads (offline), so the only thing to show is the
            // pre-cached thumbnail.
            config.dataLoader = StubDataLoader(result: .failure(URLError(.notConnectedToInternet)))
            config.imageCache = memoryCache
        }
        // Seed the thumbnail under the SAME key the feed cell warms it: the
        // downsample request, not the bare url request.
        let downsampleRequest = ImageService.downsampleRequest(
            url: thumbUrl,
            pointSize: ImageService.feedThumbnailPointSize
        )
        pipeline.cache[downsampleRequest] = ImageContainer(image: ImageFixture.image())

        let service = ImageService(alertService: AlertService(), pipeline: pipeline)

        var loadingThumbnail: UIImage?
        for await state in service.fetch(fullUrl, thumbnail: thumbUrl) {
            if case let .loading(thumbnail) = state, thumbnail != nil {
                loadingThumbnail = thumbnail
            }
        }
        #expect(
            loadingThumbnail != nil,
            "Expected .loading to surface the thumbnail cached under the downsampled feed key"
        )
    }

    @Test
    func fullFetch_failure_yieldsFailureAndAlerts() async throws {
        let url = try #require(URL(string: "https://example.com/bad.png"))
        let alert = SpyAlertService()
        let pipeline = ImagePipeline { config in
            config.dataLoader = StubDataLoader(result: .failure(URLError(.timedOut)))
            config.imageCache = nil
        }
        let service = ImageService(alertService: alert, pipeline: pipeline)

        var sawFailure = false
        for await state in service.fetch(url, thumbnail: nil) {
            if case .failure = state { sawFailure = true }
        }
        #expect(sawFailure)
        #expect(alert.imageErrors == [url])
    }

    @Test
    func fullFetch_memoryCacheHit_yieldsReady() async throws {
        let url = try #require(URL(string: "https://example.com/cached.png"))
        let pipeline = ImagePipeline { config in
            config.dataLoader = StubDataLoader(result: .failure(URLError(.notConnectedToInternet)))
            config.imageCache = ImageCache()
        }
        pipeline.cache[ImageRequest(url: url)] = ImageContainer(image: ImageFixture.image())
        let service = ImageService(alertService: AlertService(), pipeline: pipeline)

        var ready: UIImage?
        for await state in service.fetch(url, thumbnail: nil) {
            if case let .ready(image) = state { ready = image }
        }
        #expect(ready != nil, "memory-cache hit must yield .ready, not hang on .loading")
    }

    @Test
    func fullFetch_throughEventStream_yieldsReady() async throws {
        let url = try #require(URL(string: "https://example.com/full.png"))
        let pipeline = ImagePipeline { config in
            config.dataLoader = StubDataLoader(result: .success((ImageFixture.pngData(), ImageFixture.httpResponse(url))))
            config.imageCache = nil
        }
        let service = ImageService(alertService: AlertService(), pipeline: pipeline)

        var lastImage: UIImage?
        for await state in service.fetch(url, thumbnail: nil) {
            if case let .ready(image) = state { lastImage = image }
        }
        #expect(lastImage != nil)
    }
}
