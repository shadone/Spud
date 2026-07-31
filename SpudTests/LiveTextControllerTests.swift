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
        await waitUntil("second analyze() call and the first call's cancellation to land") {
            analyzer.analyzeCallCount == 2 && analyzer.cancelledCallCount == 1
        }

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
        await waitUntil("the in-flight analyze() call to be cancelled") {
            analyzer.cancelledCallCount == 1
        }

        #expect(analyzer.cancelledCallCount == 1)
    }
}
