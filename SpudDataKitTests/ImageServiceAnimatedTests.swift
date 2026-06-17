//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Nuke
import XCTest
@testable import SpudDataKit

final class ImageServiceAnimatedTests: XCTestCase {
    func test_animatedImageData_returnsOriginalBytes() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/a.gif"))
        let bytes = ImageFixture.pngData() // any non-empty bytes; we assert round-trip
        let pipeline = ImagePipeline { config in
            config.dataLoader = StubDataLoader(result: .success((bytes, ImageFixture.httpResponse(url))))
            config.imageCache = nil
        }
        let service = ImageService(alertService: AlertService(), pipeline: pipeline)

        let result = await service.animatedImageData(url)
        XCTAssertEqual(result, bytes)
    }
}
