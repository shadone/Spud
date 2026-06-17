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
}
