//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import UIKit
import XCTest
@testable import Spud

/// Verifies the full-screen media viewer shows its loading indicator only while
/// the final full-resolution image is still in flight — on a short grace delay,
/// so a fast load or cache hit never flashes the spinner — and hides it on
/// `.ready` / `.failure`.
@MainActor
final class ZoomableImageViewLoadingIndicatorTests: XCTestCase {
    private let screen = CGSize(width: 390, height: 844)

    private func solidImage(
        _ color: UIColor = .systemTeal,
        size: CGSize = CGSize(width: 64, height: 64)
    ) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func makeView(
        item: MediaItem,
        imageService: ImageServiceType
    ) -> ZoomableImageView {
        let view = ZoomableImageView(item: item, imageService: imageService)
        view.frame = CGRect(origin: .zero, size: screen)
        view.backgroundColor = .black
        view.layoutIfNeeded()
        return view
    }

    /// With a preloaded thumbnail, `startLoading()` must not start the spinner
    /// synchronously — the grace task has not fired, so there's no flash.
    func test_indicatorDoesNotShowSynchronously() {
        let item = MediaItem(
            imageUrl: URL(filePath: "/full.png"),
            thumbnailUrl: URL(filePath: "/thumb.png"),
            preloadedImage: solidImage()
        )
        let view = makeView(
            item: item,
            imageService: FakeImageService([.loadingForever])
        )

        view.startLoading()

        XCTAssertFalse(view.isLoadingIndicatorVisible)
    }

    /// When the grace timer fires while the final image is still loading, the
    /// decision method starts the spinner.
    func test_indicatorShowsWhenGraceFiresWhileStillLoading() {
        let item = MediaItem(imageUrl: URL(filePath: "/full.png"))
        let view = makeView(
            item: item,
            imageService: FakeImageService([.loadingForever])
        )

        view.startLoading()
        view.presentIndicatorIfStillLoading()

        XCTAssertTrue(view.isLoadingIndicatorVisible)
    }

    /// A cache hit / fast load resolves to `.ready` before the grace timer; the
    /// decision method called afterwards must be a no-op (spinner stays hidden).
    func test_indicatorIsNoOpAfterReady() async {
        let item = MediaItem(imageUrl: URL(filePath: "/full.png"))
        let view = makeView(
            item: item,
            imageService: FakeImageService([.ready(solidImage())])
        )

        view.startLoading()
        await view.awaitLoadForTesting()

        view.presentIndicatorIfStillLoading()

        XCTAssertFalse(view.isLoadingIndicatorVisible)
    }

    /// A failure resolves the load; the decision method called afterwards must be
    /// a no-op (the spinner stays hidden even if the grace decision runs).
    func test_indicatorIsNoOpAfterFailure() async {
        let item = MediaItem(imageUrl: URL(filePath: "/full.png"))
        let view = makeView(
            item: item,
            imageService: FakeImageService([.failure])
        )

        view.startLoading()
        await view.awaitLoadForTesting()

        view.presentIndicatorIfStillLoading()

        XCTAssertFalse(view.isLoadingIndicatorVisible)
    }

    /// On failure with no preloaded image, the spinner is hidden and the
    /// broken-image icon is shown.
    func test_failureHidesIndicatorAndShowsError() async {
        let item = MediaItem(imageUrl: URL(filePath: "/full.png"))
        let view = makeView(
            item: item,
            imageService: FakeImageService([.failure])
        )

        view.startLoading()
        await view.awaitLoadForTesting()

        XCTAssertFalse(view.isLoadingIndicatorVisible)
        XCTAssertNil(view.image)
        XCTAssertFalse(view.isErrorIconHiddenForTesting)
    }
}

/// A deterministic `ImageServiceType` for these tests, modelled on
/// `ScriptedImageService`. Only `fetch(_:thumbnail:)` is implemented; the
/// protocol's default implementations cover the rest.
private final class FakeImageService: ImageServiceType, @unchecked Sendable {
    enum Response {
        /// Yield `.loading` then `.ready(image)`, then finish.
        case ready(UIImage)
        /// Yield `.loading` then `.failure`, then finish.
        case failure
        /// Yield `.loading` and never finish — models an in-flight fetch.
        case loadingForever
    }

    private let responses: [Response]
    private let lock = NSLock()
    private var callIndex = 0

    init(_ responses: [Response]) {
        self.responses = responses.isEmpty ? [.failure] : responses
    }

    func fetch(
        _ url: URL,
        thumbnail thumbnailUrl: URL?
    ) -> AsyncStream<ImageLoadingState> {
        let response: Response = {
            lock.lock()
            defer { lock.unlock() }
            let index = min(callIndex, responses.count - 1)
            callIndex += 1
            return responses[index]
        }()

        return AsyncStream { continuation in
            continuation.yield(.loading(thumbnail: nil))
            switch response {
            case let .ready(image):
                continuation.yield(.ready(image))
                continuation.finish()
            case .failure:
                continuation.yield(.failure)
                continuation.finish()
            case .loadingForever:
                break
            }
        }
    }
}
