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

    /// Maps each `analyze` call's unique id to its continuation, ensuring that
    /// cancellation of one call does not affect another concurrent call.
    private var pendingContinuations: [UUID: CheckedContinuation<Void, Error>] = [:]

    init(isSupported: Bool = true) {
        self.isSupported = isSupported
    }

    func analyze(_: UIImage) async throws -> ImageAnalysis? {
        analyzeCallCount += 1
        guard blocksUntilResumed else { return nil }

        let callID = UUID()

        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    // If the task is already cancelled, resume immediately with the error
                    // instead of registering a continuation that nobody will ever resume.
                    if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        pendingContinuations[callID] = continuation
                    }
                }
            } onCancel: {
                Task { @MainActor in self.failPending(callID: callID) }
            }
        } catch {
            cancelledCallCount += 1
            throw error
        }
        return nil
    }

    /// Lets every suspended `analyze` call return.
    func resumePendingAnalysis() {
        let continuations = pendingContinuations.values
        pendingContinuations = [:]
        for continuation in continuations {
            continuation.resume()
        }
    }

    /// Fails a specific call's continuation with the given error. If the call has
    /// already been resumed (e.g., by `resumePendingAnalysis`), this is a no-op.
    private func failPending(callID: UUID) {
        guard let continuation = pendingContinuations.removeValue(forKey: callID) else {
            return
        }
        continuation.resume(throwing: CancellationError())
    }
}
