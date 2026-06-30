//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SBTUITestTunnelClient
import UIKit
import XCTest

/// iPad-only UITest verifying that opening a community from the Discover screen
/// pushes a two-column `CommunityReadingSplitViewController` (regular-width gate)
/// with the "No posts selected" placeholder in the secondary column.
///
/// Skipped on iPhone: the same tap path produces a single-column
/// `CommunityOrLoadingViewController` push on compact width.
class IPadSplitUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false

        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("iPad-specific test; skipped on non-iPad devices")
        }

        app = SBTUITunneledApplication()
        let launchOptions: [String] = [
            SBTUITunneledApplicationLaunchOptionResetFilesystem,
            SBTUITunneledApplicationLaunchOptionDisableUITextFieldAutocomplete,
            AppLaunchArgument.staticImageService.rawValue,
            AppLaunchArgument.seedSignedOutDefaultAccount.rawValue,
        ]
        app.launchTunnel(withOptions: launchOptions) {
            self.app.monitorRequests(matching: SBTRequestMatch(url: ".*"))

            // Catch-all 500 for any endpoint we don't explicitly stub.
            _ = self.app.stubRequests(
                matching: SBTRequestMatch(url: ".*"),
                response: SBTStubResponse(response: "", returnCode: 500)
            )

            // Stub the community info fetch triggered when CommunityOrLoadingViewController
            // loads. The wildcard URL matches any host's /api/v3/community endpoint.
            _ = self.app.stubRequests(
                matching: SBTRequestMatch(
                    url: ".*/api/v3/community",
                    method: "GET"
                ),
                response: SBTStubResponse(fileNamed: "community-tincidunt.json")
            )

            // Stub the Lemmy Explorer (data.lemmyverse.net) multipart community
            // directory. With ResetFilesystem the DB is empty and the bundled seed
            // import is async — it may not complete within the 10-second cell wait.
            // Stubbing the network endpoints lets the ExplorerService refresh succeed
            // immediately so Discover cells appear before the timeout.
            //
            // Pattern order: specific before catch-all (SBT evaluates in reverse
            // registration order — later stubs win). The metadata endpoint returns
            // { "count": 1 } and the single part returns one community DTO.
            _ = self.app.stubRequests(
                matching: SBTRequestMatch(url: ".*data\\.lemmyverse\\.net/data/community/0\\.json"),
                response: SBTStubResponse(fileNamed: "explorer-community-0.json")
            )
            _ = self.app.stubRequests(
                matching: SBTRequestMatch(url: ".*data\\.lemmyverse\\.net/data/community\\.json"),
                response: SBTStubResponse(fileNamed: "explorer-community-meta.json")
            )
        }
    }

    override func tearDownWithError() throws {
        let allRequestUrls = app.monitoredRequestsFlushAll().map { request in
            let httpMethod = request.request!.httpMethod!
            let url = request.request!.url!.absoluteString
            return " - \(httpMethod) \(url)"
        }
        .joined(separator: "\n")
        print("### Network requests intercepted during the test:\n\(allRequestUrls)")
    }

    /// Opening a community from Discover on iPad (regular width) pushes a two-column
    /// `CommunityReadingSplitViewController`. The secondary column shows "No posts selected"
    /// before any post is tapped.
    ///
    /// The test asserts that BOTH columns are simultaneously visible and that the primary
    /// column is geometrically LEFT of the secondary column, proving a two-column layout
    /// rather than a single-column push. Passing on a single-column layout is not possible
    /// because the "Back to Communities" back button only appears in the primary column's
    /// nav bar of the split, while "No posts selected" lives in the secondary column.
    func test_discoverCommunity_showsTwoColumnSplit() {
        // Navigate to the Communities tab (Posts | Communities | Search | Inbox | Account).
        // On iPad (iOS 18+) UITabBarController renders as a sidebar — `app.tabBars` finds
        // nothing because there is no UITabBar element. The sidebar tab items are exposed as
        // plain buttons in the accessibility hierarchy; `app.buttons["Communities"]` matches
        // both the traditional bottom tab-bar button (iPhone / compact) and the sidebar item
        // (iPad regular width).
        // On iOS 26 iPad the floating tab bar exposes each item as two nested button elements
        // (outer `_UIFloatingTabBarItemCell` + inner `_UIFloatingTabBarItemView` — both inherit
        // the "Communities" label). `.firstMatch` resolves the outermost one unambiguously.
        let communitiesTab = app.buttons["Communities"].firstMatch
        XCTAssertTrue(communitiesTab.waitForExistence(timeout: 10), "Communities tab button not found")
        communitiesTab.tap()

        // Tap the Discover communities entry point in the subscriptions view.
        // On this screen the entry renders as a `UICollectionViewCell` containing a
        // StaticText (not a Button). Tap the StaticText label directly — UICollectionView
        // forwards the tap to the cell's selection handler.
        let discoverEntry = app.staticTexts["Discover communities"].firstMatch
        XCTAssertTrue(discoverEntry.waitForExistence(timeout: 10), "Discover communities entry not found")
        discoverEntry.tap()

        // Wait for a directory community row to appear and tap it.
        //
        // `DiscoverCommunityRow` is a SwiftUI view with `.accessibilityAddTraits(.isButton)` —
        // it is exposed as a **button** (not a cell) in the XCUITest accessibility tree.
        // `app.cells` always returns empty here because there are no UITableViewCell /
        // UICollectionViewCell elements in the Discover screen.
        //
        // The accessibility label for every directory row ends with "N subscribers"
        // (e.g. "Technology, c/technology@lemmy.ml, 50K subscribers"), which is unique to
        // `DiscoverCommunityRow` — trend cards say "active this week" instead. This predicate
        // reliably picks the first directory entry without matching nav/tab buttons, so it
        // cannot accidentally tap a Communities tab button or a navigation title.
        //
        // The timeout is 20 s to accommodate the first-launch bundled seed import
        // (~4.9 MB .lzfse file seeded asynchronously by ExplorerService at startup).
        let firstCommunityRow = app.buttons
            .matching(NSPredicate(format: "label CONTAINS 'subscribers'"))
            .firstMatch
        XCTAssertTrue(
            firstCommunityRow.waitForExistence(timeout: 20),
            "No directory community rows appeared in Discover (expected buttons with 'subscribers' in label)"
        )
        firstCommunityRow.tap()

        // The secondary column of CommunityReadingSplitViewController shows the
        // "No posts selected" placeholder immediately, before any post is tapped.
        let placeholder = app.staticTexts["No posts selected"]
        XCTAssertTrue(
            placeholder.waitForExistence(timeout: 10),
            "Expected 'No posts selected' placeholder in the secondary column of the reading split"
        )

        // Dual-column proof: the "Back to Communities" button is injected by
        // CommunityReadingSplitViewController.makeBackButton() onto the primary column's
        // navigation bar via UINavigationControllerDelegate. It only exists when the split
        // VC is on screen — a single-column CommunityOrLoadingViewController push does NOT
        // produce this button. Asserting BOTH elements are simultaneously present proves
        // that two columns are rendered at the same time.
        let backButton = app.buttons["Back to Communities"]
        XCTAssertTrue(
            backButton.exists,
            "Primary column back button 'Back to Communities' not found — expected both columns to be visible simultaneously"
        )

        // Horizontal layout proof: the primary column (left) must be geometrically left
        // of the secondary column placeholder (right). Both frames are in application
        // screen coordinates after the layout has settled (the placeholder
        // waitForExistence above ensures the split is on screen before frames are read).
        //
        // Comparison uses midX rather than minX: the placeholder label is constrained
        // to span the full width of the secondary column's view (leading → trailing), so
        // its minX is 0 in UIKit coordinates, whereas the back button is a narrow bar
        // item with minX ≈ 14. Using midX captures where each element is centred,
        // which is a reliable geometric discriminant for left-column vs right-column.
        let primaryMidX = backButton.frame.midX
        let secondaryMidX = placeholder.frame.midX
        XCTAssertLessThan(
            primaryMidX,
            secondaryMidX,
            "Primary column (midX \(primaryMidX)) should be left of secondary column (midX \(secondaryMidX))"
        )
    }
}
