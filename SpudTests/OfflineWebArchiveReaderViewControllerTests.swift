//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
import UIKit
@testable import Spud

/// Construction / smoke coverage for the offline reader. The actual `WKWebView`
/// archive render is not unit-testable (it needs a real web view + run loop), so
/// these tests verify the VC and its modal wrapper build and configure their
/// chrome without crashing.
@MainActor
struct OfflineWebArchiveReaderViewControllerTests {
    private let archiveFileURL = URL(fileURLWithPath: "/tmp/spud-test/abc123.webarchive")
    private let originalURL = URL(string: "https://example.com/article")!

    @Test
    func builds_withFileURL() {
        let viewController = OfflineWebArchiveReaderViewController(
            archiveFileURL: archiveFileURL,
            originalURL: originalURL,
            title: "An Article"
        )
        // Forcing the view to load configures the navigation chrome.
        viewController.loadViewIfNeeded()

        #expect(viewController.title == "An Article")
        #expect(viewController.navigationItem.leftBarButtonItem != nil)
        // Overflow + share live on the right.
        #expect(viewController.navigationItem.rightBarButtonItems?.count == 2)
        #expect(viewController.navigationItem.titleView != nil)
    }

    @Test
    func builds_fallsBackToHost_whenNoTitle() {
        let viewController = OfflineWebArchiveReaderViewController(
            archiveFileURL: archiveFileURL,
            originalURL: originalURL,
            title: nil
        )
        viewController.loadViewIfNeeded()

        // With no stored or page title, the host is used as the title.
        #expect(viewController.title == "example.com")
    }

    @Test
    func makeModal_wrapsInNavigationController() {
        let navigationController = OfflineWebArchiveReaderViewController.makeModal(
            archiveFileURL: archiveFileURL,
            originalURL: originalURL,
            title: "An Article"
        )
        #expect(navigationController.viewControllers.count == 1)
        #expect(navigationController.viewControllers.first is OfflineWebArchiveReaderViewController)
    }
}
