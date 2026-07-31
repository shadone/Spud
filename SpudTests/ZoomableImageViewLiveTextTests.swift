//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import Testing
import UIKit
@testable import Spud

/// Verifies the media viewer's zoomable image view drives Live Text correctly:
/// only the final image is analyzed, animated items are skipped, and the
/// VoiceOver element moves aside so the Live Text button stays reachable.
@MainActor
struct ZoomableImageViewLiveTextTests {
    private let screen = CGSize(width: 390, height: 844)

    private func solidImage(
        _ color: UIColor = .systemTeal,
        size: CGSize = CGSize(width: 64, height: 64)
    ) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func makeView(
        item: MediaItem,
        imageService: ImageServiceType,
        analyzer: FakeImageTextAnalyzer
    ) -> ZoomableImageView {
        let view = ZoomableImageView(
            item: item,
            imageService: imageService,
            liveTextAnalyzer: analyzer
        )
        view.frame = CGRect(origin: .zero, size: screen)
        view.layoutIfNeeded()
        return view
    }

    /// A thumbnail that arrives over the network on the loading path — not the
    /// final image, and not a `preloadedImage` handed in up front — must not be
    /// analyzed, even while the full-resolution fetch is still in flight.
    ///
    /// Drives the load with `.loadingForeverWithThumbnail` so `startLoading()`'s
    /// `.loading` branch actually runs and puts the thumbnail on screen, then
    /// waits for that to happen before asserting. A synchronous assertion right
    /// after `startLoading()` would pass no matter what that branch does: the
    /// load task is an unstructured `Task`, and a synchronous `@MainActor` test
    /// body never yields, so the task never gets a chance to run before the
    /// assertion executes. `.loadingForeverWithThumbnail` never finishes its
    /// stream, so `awaitLoadForTesting()` would hang — waiting for the
    /// thumbnail's visible effect is the only way to observe that the branch
    /// ran without hanging.
    ///
    /// After the thumbnail lands, also await the analysis seam. If the
    /// `.loading` branch were to wrongly treat the thumbnail as final, analysis
    /// starts as its *own* unstructured `Task` (spawned from inside the load
    /// task) — a bare `waitUntil` on `view.image` can observe the thumbnail
    /// before that grandchild task has run even once, letting the assertion
    /// below race ahead of it and pass regardless of the bug.
    /// `awaitLiveTextAnalysisForTesting()` is safe to call unconditionally: on
    /// the correct path no analysis is ever started, so it resolves immediately.
    @Test
    func doesNotAnalyzeANetworkThumbnail() async {
        let analyzer = FakeImageTextAnalyzer()
        let thumbnail = solidImage(.systemIndigo)
        let view = makeView(
            item: MediaItem(
                imageUrl: URL(filePath: "/full.png"),
                thumbnailUrl: URL(filePath: "/thumb.png")
            ),
            imageService: FakeImageService([.loadingForeverWithThumbnail(thumbnail)]),
            analyzer: analyzer
        )

        view.setPageCurrent(true)
        view.startLoading()

        await waitUntil("thumbnail arrives on screen") { view.image != nil }
        await view.awaitLiveTextAnalysisForTesting()

        #expect(analyzer.analyzeCallCount == 0)
    }

    @Test
    func analyzesTheFinalImageOnTheCurrentPage() async {
        let analyzer = FakeImageTextAnalyzer()
        let view = makeView(
            item: MediaItem(imageUrl: URL(filePath: "/full.png")),
            imageService: FakeImageService([.ready(solidImage())]),
            analyzer: analyzer
        )

        view.setPageCurrent(true)
        view.startLoading()
        await view.awaitLoadForTesting()
        await view.awaitLiveTextAnalysisForTesting()

        #expect(analyzer.analyzeCallCount == 1)
    }

    @Test
    func doesNotAnalyzeAnAnimatedItem() async {
        let analyzer = FakeImageTextAnalyzer()
        let view = makeView(
            item: MediaItem(imageUrl: URL(filePath: "/animation.gif")),
            imageService: FakeImageService([.ready(solidImage())]),
            analyzer: analyzer
        )

        view.setPageCurrent(true)
        view.startLoading()
        await view.awaitLoadForTesting()
        await view.awaitLiveTextAnalysisForTesting()

        #expect(analyzer.analyzeCallCount == 0)
    }

    /// Before Live Text is active the image view carries the VoiceOver element
    /// itself, exactly as it did before this feature.
    @Test
    func imageViewIsTheAccessibilityElementByDefault() {
        let view = makeView(
            item: MediaItem(imageUrl: URL(filePath: "/full.png")),
            imageService: FakeImageService([.loadingForever]),
            analyzer: FakeImageTextAnalyzer()
        )

        #expect(view.isImageAccessibilityElementForTesting)
        #expect(view.liveTextDescriptionElementLabelForTesting == nil)
    }

    /// Once Live Text is active the image view must stop being an accessibility
    /// element, or it would hide the Live Text button VisionKit adds as its
    /// subview from VoiceOver. The image's own description moves to a dedicated
    /// element so it is not lost.
    @Test
    func liveTextMovesTheAccessibilityElementAside() {
        let view = makeView(
            item: MediaItem(imageUrl: URL(filePath: "/full.png")),
            imageService: FakeImageService([.loadingForever]),
            analyzer: FakeImageTextAnalyzer()
        )

        view.setLiveTextActive(true)

        #expect(!view.isImageAccessibilityElementForTesting)
        #expect(view.liveTextDescriptionElementLabelForTesting == "Image")
    }

    @Test
    func accessibilityElementIsRestoredWhenLiveTextGoesAway() {
        let view = makeView(
            item: MediaItem(imageUrl: URL(filePath: "/full.png")),
            imageService: FakeImageService([.loadingForever]),
            analyzer: FakeImageTextAnalyzer()
        )

        view.setLiveTextActive(true)
        view.setLiveTextActive(false)

        #expect(view.isImageAccessibilityElementForTesting)
        #expect(view.liveTextDescriptionElementLabelForTesting == nil)
    }
}
