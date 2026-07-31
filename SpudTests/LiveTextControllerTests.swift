//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
import UIKit
@testable import Spud

/// Verifies when the media viewer decides to run Live Text analysis: only on a
/// supported device, only for a non-animated item, only for the final
/// full-resolution image, and only while its page is the one on screen.
@MainActor
struct LiveTextControllerTests {
    private func image(_ size: CGSize = CGSize(width: 32, height: 32)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func makeController(
        analyzer: FakeImageTextAnalyzer,
        isEnabled: Bool = true
    ) -> LiveTextController {
        let controller = LiveTextController(analyzer: analyzer, isEnabled: isEnabled)
        controller.attach(to: UIImageView())
        return controller
    }

    /// Cancelling `FakeImageTextAnalyzer`'s in-flight `analyze()` resolves over
    /// several actor hops (its `onCancel` handler spawns a `Task` that resumes a
    /// continuation, which in turn resumes the original call), and this test
    /// host boots the full app with its own background activity contending for
    /// the main actor. A single `Task.yield()` is not enough to guarantee that
    /// chain has drained; yielding a generous, fixed number of times converges
    /// reliably without depending on wall-clock time (never `Task.sleep`).
    private func yieldUntilCancellationPropagates() async {
        for _ in 0..<50 {
            await Task.yield()
        }
    }

    @Test
    func doesNotAnalyzeWhenAnalyzerIsUnsupported() async {
        let analyzer = FakeImageTextAnalyzer(isSupported: false)
        let controller = makeController(analyzer: analyzer)

        controller.setPageCurrent(true)
        controller.setFinalImage(image())
        await controller.awaitAnalysisForTesting()

        #expect(analyzer.analyzeCallCount == 0)
    }

    @Test
    func doesNotAnalyzeAnimatedItem() async {
        let analyzer = FakeImageTextAnalyzer()
        let controller = makeController(analyzer: analyzer, isEnabled: false)

        controller.setPageCurrent(true)
        controller.setFinalImage(image())
        await controller.awaitAnalysisForTesting()

        #expect(analyzer.analyzeCallCount == 0)
    }

    @Test
    func doesNotAnalyzeBeforeThePageIsCurrent() async {
        let analyzer = FakeImageTextAnalyzer()
        let controller = makeController(analyzer: analyzer)

        controller.setFinalImage(image())
        await controller.awaitAnalysisForTesting()

        #expect(analyzer.analyzeCallCount == 0)
    }

    @Test
    func analyzesOnceThePageBecomesCurrent() async {
        let analyzer = FakeImageTextAnalyzer()
        let controller = makeController(analyzer: analyzer)

        controller.setFinalImage(image())
        controller.setPageCurrent(true)
        await controller.awaitAnalysisForTesting()

        #expect(analyzer.analyzeCallCount == 1)
    }

    /// The same image arriving twice (a layout pass re-setting it) must not
    /// re-run analysis.
    @Test
    func doesNotReanalyzeTheSameImage() async {
        let analyzer = FakeImageTextAnalyzer()
        let controller = makeController(analyzer: analyzer)
        let sameImage = image()

        controller.setPageCurrent(true)
        controller.setFinalImage(sameImage)
        await controller.awaitAnalysisForTesting()
        controller.setFinalImage(sameImage)
        await controller.awaitAnalysisForTesting()

        #expect(analyzer.analyzeCallCount == 1)
    }

    /// Full resolution replacing an earlier final image re-runs analysis on the
    /// better pixels, cancelling the in-flight pass.
    @Test
    func reanalyzesWhenAHigherResolutionImageArrives() async {
        let analyzer = FakeImageTextAnalyzer()
        analyzer.blocksUntilResumed = true
        let controller = makeController(analyzer: analyzer)

        controller.setPageCurrent(true)
        controller.setFinalImage(image(CGSize(width: 32, height: 32)))
        await Task.yield()
        controller.setFinalImage(image(CGSize(width: 64, height: 64)))
        await yieldUntilCancellationPropagates()

        #expect(analyzer.analyzeCallCount == 2)
        #expect(analyzer.cancelledCallCount == 1)

        analyzer.resumePendingAnalysis()
        await controller.awaitAnalysisForTesting()
    }

    @Test
    func cancelsAnalysisWhenThePageIsNoLongerCurrent() async {
        let analyzer = FakeImageTextAnalyzer()
        analyzer.blocksUntilResumed = true
        let controller = makeController(analyzer: analyzer)

        controller.setPageCurrent(true)
        controller.setFinalImage(image())
        await Task.yield()
        controller.setPageCurrent(false)
        await yieldUntilCancellationPropagates()

        #expect(analyzer.cancelledCallCount == 1)
    }
}
