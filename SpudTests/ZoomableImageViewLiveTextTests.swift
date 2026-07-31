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

    /// A preloaded thumbnail is not the final image and must not be analyzed.
    @Test
    func doesNotAnalyzeAPreloadedThumbnail() {
        let analyzer = FakeImageTextAnalyzer()
        let view = makeView(
            item: MediaItem(
                imageUrl: URL(filePath: "/full.png"),
                thumbnailUrl: URL(filePath: "/thumb.png"),
                preloadedImage: solidImage()
            ),
            imageService: FakeImageService([.loadingForever]),
            analyzer: analyzer
        )

        view.setPageCurrent(true)
        view.startLoading()

        // No `awaitLoadForTesting()` here: `.loadingForever` never finishes its
        // stream, so awaiting it would hang forever. That's fine — the preloaded
        // thumbnail was set synchronously in `init`, before `startLoading()` even
        // runs, and it is never the final image, so it can't have triggered
        // analysis regardless of how the full-resolution load later resolves.
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
