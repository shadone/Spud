//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Nuke
import Testing
@testable import SpudDataKit

struct ImageServiceMappingTests {
    @Test
    func pipelineCancelled_isCancellation() {
        let error: Error = ImagePipeline.Error.cancelled
        #expect(error.isImageLoadingCancellation)
    }

    @Test
    func swiftCancellation_isCancellation() {
        let error: Error = CancellationError()
        #expect(error.isImageLoadingCancellation)
    }

    @Test
    func dataLoadingFailure_isNotCancellation() {
        let underlying = URLError(.timedOut)
        let error: Error = ImagePipeline.Error.dataLoadingFailed(error: underlying)
        #expect(!(error.isImageLoadingCancellation))
    }

    @Test
    func mapper_dataLoadingFailed_mapsToNetwork() {
        let underlying = URLError(.timedOut)
        let mapped = ImageService.imageLoadingError(from: .dataLoadingFailed(error: underlying))
        guard case let .network(error) = mapped else { Issue.record("expected .network")
            return
        }
        #expect((error as? URLError)?.code == .timedOut)
    }

    @Test
    func mapper_dataIsEmpty_mapsToCannotDecode() {
        let mapped = ImageService.imageLoadingError(from: .dataIsEmpty)
        guard case .cannotDecode = mapped else { Issue.record("expected .cannotDecode")
            return
        }
    }

    @Test
    func mapper_cancelled_mapsToNetwork() {
        let mapped = ImageService.imageLoadingError(from: .cancelled)
        guard case .network = mapped else { Issue.record("expected .network (default arm)")
            return
        }
    }

    @Test
    func wrappedNetworkCancellation_isCancellation() {
        let error: Error = ImageLoadingError.network(URLError(.cancelled))
        #expect(error.isImageLoadingCancellation)
    }
}
