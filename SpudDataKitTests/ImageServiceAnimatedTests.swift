//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Nuke
import Testing
@testable import SpudDataKit

struct ImageServiceAnimatedTests {
    @Test
    func animatedImageData_returnsOriginalBytes() async throws {
        let url = try #require(URL(string: "https://example.com/a.gif"))
        let bytes = ImageFixture.pngData() // any non-empty bytes; we assert round-trip
        let pipeline = ImagePipeline { config in
            config.dataLoader = StubDataLoader(result: .success((bytes, ImageFixture.httpResponse(url))))
            config.imageCache = nil
        }
        let service = ImageService(alertService: AlertService(), pipeline: pipeline)

        let result = await service.animatedImageData(url)
        #expect(result == bytes)
    }
}
