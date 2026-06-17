//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Nuke
import UIKit
import XCTest
@testable import SpudDataKit

final class ImageServiceFullFetchTests: XCTestCase {
    func test_fullFetch_yieldsReadyImage() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/full.png"))
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
        XCTAssertNotNil(lastImage)
    }

    func test_fullFetch_seedsThumbnailFromMemoryCache() async throws {
        let fullUrl = try XCTUnwrap(URL(string: "https://example.com/full.png"))
        let thumbUrl = try XCTUnwrap(URL(string: "https://example.com/thumb.png"))

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
        XCTAssertNotNil(loadingThumbnail, "Expected .loading to be seeded with the cached thumbnail image")
    }

    func test_fullFetch_failure_yieldsFailureAndAlerts() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/bad.png"))
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
        XCTAssertTrue(sawFailure)
        XCTAssertEqual(alert.imageErrors, [url])
    }

    func test_fullFetch_memoryCacheHit_yieldsReady() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/cached.png"))
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
        XCTAssertNotNil(ready, "memory-cache hit must yield .ready, not hang on .loading")
    }

    func test_fullFetch_throughEventStream_yieldsReady() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/full.png"))
        let pipeline = ImagePipeline { config in
            config.dataLoader = StubDataLoader(result: .success((ImageFixture.pngData(), ImageFixture.httpResponse(url))))
            config.imageCache = nil
        }
        let service = ImageService(alertService: AlertService(), pipeline: pipeline)

        var lastImage: UIImage?
        for await state in service.fetch(url, thumbnail: nil) {
            if case let .ready(image) = state { lastImage = image }
        }
        XCTAssertNotNil(lastImage)
    }
}
