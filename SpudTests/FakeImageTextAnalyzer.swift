//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit
import VisionKit
@testable import Spud

/// Records analysis requests so tests can assert *when* the viewer decides to
/// analyze. Always resolves to `nil` — `ImageAnalysis` has no public
/// initializer, so the analysis-assignment path is verified on device, not here.
@MainActor
final class FakeImageTextAnalyzer: ImageTextAnalyzing {
    var isSupported: Bool

    /// How many times `analyze` was entered.
    private(set) var analyzeCallCount = 0

    /// How many in-flight analyses were cancelled before completing.
    private(set) var cancelledCallCount = 0

    /// When true, `analyze` suspends until `resumePendingAnalysis()` is called,
    /// so a test can observe an in-flight analysis and cancel it.
    var blocksUntilResumed = false

    private var pendingContinuations: [CheckedContinuation<Void, Error>] = []

    init(isSupported: Bool = true) {
        self.isSupported = isSupported
    }

    func analyze(_: UIImage) async throws -> ImageAnalysis? {
        analyzeCallCount += 1
        guard blocksUntilResumed else { return nil }
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    pendingContinuations.append(continuation)
                }
            } onCancel: {
                Task { @MainActor in self.failPending(with: CancellationError()) }
            }
        } catch {
            cancelledCallCount += 1
            throw error
        }
        return nil
    }

    /// Lets every suspended `analyze` call return.
    func resumePendingAnalysis() {
        let continuations = pendingContinuations
        pendingContinuations = []
        for continuation in continuations {
            continuation.resume()
        }
    }

    private func failPending(with error: Error) {
        let continuations = pendingContinuations
        pendingContinuations = []
        for continuation in continuations {
            continuation.resume(throwing: error)
        }
    }
}
