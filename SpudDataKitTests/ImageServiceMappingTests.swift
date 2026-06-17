//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Nuke
import XCTest
@testable import SpudDataKit

final class ImageServiceMappingTests: XCTestCase {
    func test_pipelineCancelled_isCancellation() {
        let error: Error = ImagePipeline.Error.cancelled
        XCTAssertTrue(error.isImageLoadingCancellation)
    }

    func test_swiftCancellation_isCancellation() {
        let error: Error = CancellationError()
        XCTAssertTrue(error.isImageLoadingCancellation)
    }

    func test_dataLoadingFailure_isNotCancellation() {
        let underlying = URLError(.timedOut)
        let error: Error = ImagePipeline.Error.dataLoadingFailed(error: underlying)
        XCTAssertFalse(error.isImageLoadingCancellation)
    }
}
