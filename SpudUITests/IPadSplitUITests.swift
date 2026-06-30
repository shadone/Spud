//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SBTUITestTunnelClient
import XCTest

/// iPad-only UITest verifying that opening a community from the Discover screen
/// pushes a two-column `CommunityReadingSplitViewController` (regular-width gate)
/// with the "No posts selected" placeholder in the secondary column.
///
/// Skipped on iPhone: the same tap path produces a single-column
/// `CommunityOrLoadingViewController` push on compact width.
class IPadSplitUITests: XCTestCase {
    var app: SBTUITunneledApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        guard XCUIDevice.shared.userInterfaceIdiom == .pad else {
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
    func test_discoverCommunity_showsTwoColumnSplit() {
        // Navigate to the Communities tab (Posts | Communities | Search | Inbox | Account).
        app.tabBars.buttons["Communities"].tap()

        // Tap the Discover communities entry point in the subscriptions view.
        let discoverButton = app.buttons["Discover communities"]
        XCTAssertTrue(discoverButton.waitForExistence(timeout: 10), "Discover communities button not found")
        discoverButton.tap()

        // Wait for the Explorer community list to appear (the bundled seed imports on first
        // launch even with ResetFilesystem) and tap the first cell.
        let firstCell = app.cells.firstMatch
        XCTAssertTrue(firstCell.waitForExistence(timeout: 10), "No community cells appeared in Discover")
        firstCell.tap()

        // The secondary column of CommunityReadingSplitViewController should show the
        // "No posts selected" placeholder immediately, before any post is tapped.
        let placeholder = app.staticTexts["No posts selected"]
        XCTAssertTrue(
            placeholder.waitForExistence(timeout: 10),
            "Expected 'No posts selected' placeholder in the secondary column of the reading split"
        )
    }
}
