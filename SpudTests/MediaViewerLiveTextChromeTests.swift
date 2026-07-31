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

/// Minimal dependency container satisfying `MediaViewerViewController.Dependencies`
/// (just `HasImageService`) — lighter than the app-wide `FakeDependencies` superset
/// since this suite only ever needs to control image loading.
private struct MediaViewerTestDependencies: HasImageService {
    let imageService: ImageServiceType
}

/// Verifies the Live Text button behaves as chrome: hidden when the viewer
/// opens clean, revealed with the top bar, hidden again with it.
@MainActor
struct MediaViewerLiveTextChromeTests {
    private func solidImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
    }

    private func makeViewController() -> MediaViewerViewController {
        let viewController = MediaViewerViewController(
            items: [MediaItem(imageUrl: URL(filePath: "/full.png"))],
            startIndex: 0,
            dependencies: MediaViewerTestDependencies(imageService: FakeImageService([.ready(solidImage())]))
        )
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.view.layoutIfNeeded()
        return viewController
    }

    /// The viewer opens with the chrome hidden, so the Live Text button starts
    /// hidden too — the photo is undecorated.
    @Test
    func buttonStartsHiddenWithTheChrome() {
        let viewController = makeViewController()

        #expect(viewController.isLiveTextButtonHiddenForTesting == true)
    }

    @Test
    func buttonFollowsTheChromeWhenToggled() {
        let viewController = makeViewController()

        viewController.toggleChromeForTesting()
        #expect(viewController.isLiveTextButtonHiddenForTesting == false)

        viewController.toggleChromeForTesting()
        #expect(viewController.isLiveTextButtonHiddenForTesting == true)
    }

    /// The first page must be marked current, or it would never analyze.
    @Test
    func firstPageIsMarkedCurrent() {
        let viewController = makeViewController()

        #expect(viewController.currentPageIsCurrentForTesting == true)
    }
}
