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
}
