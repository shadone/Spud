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

struct ImageServicePrefetchTests {
    @Test
    func downsampleRequest_matchesFetchTarget() throws {
        let url = try #require(URL(string: "https://example.com/x.png"))
        let size = CGSize(width: 64, height: 64)
        let request = ImageService.downsampleRequest(url: url, pointSize: size)
        #expect(request.url == url)
        #expect(request.processors.count == 1, "exactly the resize processor")
    }

    @Test
    func prefetch_callsAreSafe() throws {
        let url = try #require(URL(string: "https://example.com/y.png"))
        let pipeline = ImagePipeline { config in
            config.dataLoader = StubDataLoader(result: .success((ImageFixture.pngData(), ImageFixture.httpResponse(url))))
            config.imageCache = nil
        }
        let service = ImageService(alertService: AlertService(), pipeline: pipeline)
        // Smoke test: start then stop must not crash and must be no-throw.
        service.startPrefetching([url], downsampleTo: CGSize(width: 64, height: 64))
        service.stopPrefetching([url], downsampleTo: CGSize(width: 64, height: 64))
    }
}
