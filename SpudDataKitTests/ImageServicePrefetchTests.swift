//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Nuke
import UIKit
import XCTest
@testable import SpudDataKit

final class ImageServicePrefetchTests: XCTestCase {
    func test_downsampleRequest_matchesFetchTarget() {
        let url = URL(string: "https://example.com/x.png")!
        let size = CGSize(width: 64, height: 64)
        let request = ImageService.downsampleRequest(url: url, pointSize: size)
        XCTAssertEqual(request.url, url)
        XCTAssertEqual(request.processors.count, 1, "exactly the resize processor")
    }

    func test_prefetch_callsAreSafe() {
        let url = URL(string: "https://example.com/y.png")!
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
