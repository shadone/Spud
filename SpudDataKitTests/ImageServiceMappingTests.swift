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

    func test_mapper_dataLoadingFailed_mapsToNetwork() {
        let underlying = URLError(.timedOut)
        let mapped = ImageService.imageLoadingError(from: .dataLoadingFailed(error: underlying))
        guard case let .network(error) = mapped else { return XCTFail("expected .network") }
        XCTAssertEqual((error as? URLError)?.code, .timedOut)
    }

    func test_mapper_dataIsEmpty_mapsToCannotDecode() {
        let mapped = ImageService.imageLoadingError(from: .dataIsEmpty)
        guard case .cannotDecode = mapped else { return XCTFail("expected .cannotDecode") }
    }

    func test_mapper_cancelled_mapsToNetwork() {
        let mapped = ImageService.imageLoadingError(from: .cancelled)
        guard case .network = mapped else { return XCTFail("expected .network (default arm)") }
    }

    func test_wrappedNetworkCancellation_isCancellation() {
        let error: Error = ImageLoadingError.network(URLError(.cancelled))
        XCTAssertTrue(error.isImageLoadingCancellation)
    }
}
