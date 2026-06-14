//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import SpudDataKit
import UIKit
import XCTest
@testable import Spud

/// Verifies the full-screen media viewer lays an aspect-fit image out centred in
/// the screen (not pinned under the safe area / top bar), and that the chrome is
/// hidden by default.
@MainActor
final class MediaViewerCenteringSnapshotTests: XCTestCase {
    private struct Deps: HasImageService {
        let imageService: ImageServiceType
    }

    private let screen = CGSize(width: 390, height: 844)

    /// A wide, short image so an aspect-fit fit-by-width leaves large top/bottom
    /// margins — making vertical centring obvious.
    private func wideImage() -> UIImage {
        let size = CGSize(width: 1400, height: 500)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setStroke()
            let border = UIBezierPath(rect: CGRect(x: 16, y: 16, width: size.width - 32, height: size.height - 32))
            border.lineWidth = 28
            border.stroke()
        }
    }

    private func item() -> MediaItem {
        MediaItem(
            imageUrl: URL(filePath: "/test.png"),
            preloadedImage: wideImage()
        )
    }

    /// The zoomable host alone: a wide image must sit centred, with equal top and
    /// bottom margins, after layout.
    func test_zoomableImageView_centresWideImage() {
        let view = ZoomableImageView(
            item: item(),
            imageService: ScriptedImageService([.loadingForever])
        )
        view.frame = CGRect(origin: .zero, size: screen)
        view.backgroundColor = .black
        view.layoutIfNeeded()
        // A second layout pass: the old frame-origin centring lost the centre
        // here; contentInset centring survives it.
        view.setNeedsLayout()
        view.layoutIfNeeded()

        assertSnapshot(
            matching: view,
            as: .image(size: screen, traits: UITraitCollection(displayScale: 2))
        )
    }

    /// Reproduces the post-list path: a small cell thumbnail is shown first
    /// (`preloadedImage`), then the full-resolution image arrives from the image
    /// service. The full image must end up centred, not pinned off-centre.
    func test_zoomableImageView_centresAfterThumbnailToFullSwap() async {
        let thumb = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256)).image { ctx in
            UIColor.systemGray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
        }
        let item = MediaItem(
            imageUrl: URL(filePath: "/full.png"),
            thumbnailUrl: URL(filePath: "/thumb.png"),
            preloadedImage: thumb
        )
        let view = ZoomableImageView(
            item: item,
            imageService: ScriptedImageService([.ready(wideImage())])
        )
        view.frame = CGRect(origin: .zero, size: screen)
        view.backgroundColor = .black
        view.layoutIfNeeded()
        // Mirror MediaViewerPageViewController.viewDidLoad: kick off the load, so
        // the scripted .ready(full) arrives and swaps the thumbnail for the full
        // image.
        view.startLoading()
        try? await Task.sleep(nanoseconds: 150_000_000)
        await Task.yield()
        view.layoutIfNeeded()

        assertSnapshot(
            matching: view,
            as: .image(size: screen, traits: UITraitCollection(displayScale: 2))
        )
    }

    /// The whole viewer: image centred and chrome (top bar, dots, pill) hidden by
    /// default.
    func test_mediaViewer_chromeHiddenByDefault() async {
        let viewer = MediaViewerViewController.make(
            items: [item()],
            dependencies: Deps(imageService: ScriptedImageService([.loadingForever]))
        )
        _ = viewer.view
        try? await Task.sleep(nanoseconds: 150_000_000)
        await Task.yield()

        assertSnapshot(
            matching: viewer,
            as: .image(on: .iPhone13Pro)
        )
    }
}
