//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Nuke
import XCTest
@testable import SpudDataKit

/// Records image errors so tests can assert whether the service alerted.
final class SpyAlertService: AlertServiceType, @unchecked Sendable {
    private(set) var imageErrors: [URL] = []

    func handle(_ error: Error, for request: AlertHandlerRequest) { }

    func image(error: ImageLoadingError, for imageUrl: URL) {
        imageErrors.append(imageUrl)
    }
}

final class ImageServiceErrorBehaviorTests: XCTestCase {
    func test_transportFailure_yieldsFailure_andAlerts() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/x.png"))
        let alert = SpyAlertService()
        let pipeline = ImagePipeline { config in
            config.dataLoader = StubDataLoader(result: .failure(URLError(.timedOut)))
            config.imageCache = nil
        }
        let service = ImageService(alertService: alert, pipeline: pipeline)

        var sawFailure = false
        for await state in service.fetch(url, downsampleTo: CGSize(width: 64, height: 64)) {
            if case .failure = state { sawFailure = true }
        }
        XCTAssertTrue(sawFailure)
        XCTAssertEqual(alert.imageErrors, [url])
    }
}
