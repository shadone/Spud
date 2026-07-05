//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SBTUITestTunnelClient
import UIKit
import XCTest

/// iPad-only UITest verifying that opening the signed-in account's **Activity**
/// area pushes a two-column `ActivitySummaryReadingSplitViewController`
/// (regular-width gate): the activity timeline in the primary column and the
/// Summary dashboard pinned in the secondary column.
///
/// ## Why a dedicated class (not a method on `IPadSplitUITests`)
///
/// `IPadSplitUITests` bakes `AppLaunchArgument.seedSignedOutDefaultAccount` into
/// every test's launch options, which lands the Account tab on the *signed-out*
/// screen (no Activity row). This test needs the *signed-in* seed
/// (`AppLaunchArgument.seedSignedInDefaultAccount`) instead, and the two seeds are
/// mutually exclusive — the signed-out seed wins if both are present (both no-op
/// once a default account exists). A per-test relaunch under SBTUITestTunnel would
/// have to re-run `launchTunnel` and re-register every stub inside the completion
/// block, so a small dedicated class with its own `setUp` is the cleaner shape
/// (and the repo prefers many small files). It keeps the iPad-only `XCTSkip` guard
/// that the sibling class uses.
///
/// ## Order-independent on a dirty simulator
///
/// The App Group `AppDatabase` survives SBT's `ResetFilesystem` AND
/// `simctl uninstall`, so a default account persisted by an earlier suite (e.g.
/// the signed-out `IPadSplitUITests`) would make the signed-in seed no-op and
/// land the Account tab on the signed-out screen — this test used to require a
/// manually-cleaned DB and failed if a signed-out suite ran first. It now passes
/// `AppLaunchArgument.wipeAppDatabase`, which deletes the on-disk database
/// directory before it opens, so the clean-DB precondition is GONE: the test is
/// self-sufficient and order-independent regardless of what ran before it.
///
/// ## What proves the two-column split
///
/// The signed-in Account tab renders from the seeded **local** person row (not a
/// spinner), and both Activity columns read **local** data (voteEvent /
/// postInteraction, empty for a fresh seed) — so no network fixture is required;
/// the catch-all 500 below absorbs any incidental refresh (a failing `getSite` is
/// harmless log noise). The assertion is therefore purely *structural*, mirroring
/// the sibling `IPadSplitUITests.test_discoverCommunity_showsTwoColumnSplit`:
///
///   - Secondary-column marker: the pinned Summary dashboard's `"Summary"` nav bar.
///     Summary is an on-screen column **only** at regular width; on a collapsed
///     single-column push the Account tab pushes a plain `ActivityViewController`
///     (no Summary column at all, reached through a nav button instead), so this
///     nav bar existing proves the two-column split rendered.
///   - Primary-column marker: the `"Back to Account"` button injected onto the
///     timeline's nav bar by `ActivitySummaryReadingSplitViewController` — present
///     only when the split VC is on screen.
///   - Horizontal geometry: the primary (timeline) column must be geometrically
///     LEFT of the secondary (Summary) column.
class IPadActivitySplitUITests: XCTestCase {
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
            // Wipe the App Group AppDatabase before it opens. It survives SBT's
            // ResetFilesystem and `simctl uninstall`, so a default account left by
            // an earlier suite on the same sim would make the signed-in seed below
            // no-op (both seeds guard on there being no default account) and land
            // the Account tab on the signed-out screen. The wipe makes this test
            // order-independent: it no longer depends on a manually-cleaned DB.
            AppLaunchArgument.wipeAppDatabase.rawValue,
            // The SIGNED-IN seed (person row + fake JWT, fixed keychainId) so the
            // Account tab shows the signed-in screen with a tappable Activity row.
            // Deliberately NOT the signed-out seed: the signed-out seed would win
            // (both no-op once a default account exists) and hide the Activity row.
            AppLaunchArgument.seedSignedInDefaultAccount.rawValue,
        ]
        app.launchTunnel(withOptions: launchOptions) {
            self.app.monitorRequests(matching: SBTRequestMatch(url: ".*"))

            // Catch-all 500 for any endpoint. The signed-in Account tab renders
            // from the seeded LOCAL person row and the Activity/Summary columns
            // read LOCAL data, so no network fixture is needed; a failing getSite
            // refresh is harmless log noise absorbed here (never a UI alert).
            _ = self.app.stubRequests(
                matching: SBTRequestMatch(url: ".*"),
                response: SBTStubResponse(response: "", returnCode: 500)
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

    /// The account's Activity area (`ActivitySummaryReadingSplitViewController`)
    /// renders as a two-column reading split on iPad regular width — the timeline
    /// in the primary column, the Summary dashboard pinned in the secondary.
    func test_accountActivity_showsTwoColumnSplit() {
        // Navigate to the Account tab. On iPad the tab bar renders as a sidebar /
        // floating tab bar whose items are plain buttons in the accessibility tree
        // (see IPadSplitUITests for why `.firstMatch` resolves the outermost one).
        let accountTab = app.buttons["Account"].firstMatch
        XCTAssertTrue(accountTab.waitForExistence(timeout: 10), "Account tab button not found")
        accountTab.tap()

        // The signed-in Account screen renders from the seeded person row (not the
        // loading spinner). Tap the "Activity" row — a SwiftUI `List` `Button`
        // (`AccountRow`) exposed as a button element with the row title as label.
        let activityRow = app.buttons["Activity"].firstMatch
        XCTAssertTrue(
            activityRow.waitForExistence(timeout: 10),
            """
            Activity row not found on the signed-in Account tab — the signed-in seed did not \
            take, so the Account tab is on the signed-out screen. DB contamination is ruled out \
            (SPUDWipeAppDatabase deletes the App Group store before launch), so suspect the seed \
            itself or a MainWindow account-routing change rather than a stale persisted account.
            """
        )
        activityRow.tap()

        // Secondary-column proof: the pinned Summary dashboard's nav bar. Summary
        // is an on-screen column only in the expanded two-column split; a
        // single-column push shows the timeline alone. `navigationBars["Summary"]`
        // matches the secondary column's nav bar (the primary column's bar is
        // titled "Activity"), so its existence proves the split rendered.
        let summaryNavBar = app.navigationBars["Summary"]
        XCTAssertTrue(
            summaryNavBar.waitForExistence(timeout: 10),
            "Expected the pinned 'Summary' dashboard in the secondary column of the reading split"
        )

        // Primary-column proof: the "Back to Account" button is injected onto the
        // timeline's nav bar by ActivitySummaryReadingSplitViewController via its
        // UINavigationControllerDelegate. It exists only when the split VC is on
        // screen — a single-column push does not produce it. Asserting BOTH markers
        // are simultaneously present proves two columns render at the same time.
        let backButton = app.buttons["Back to Account"]
        XCTAssertTrue(
            backButton.exists,
            "Primary column back button 'Back to Account' not found — expected both columns visible simultaneously"
        )

        // Horizontal layout proof: the primary (timeline) column must be
        // geometrically LEFT of the secondary (Summary) column. The back button is
        // a narrow bar item pinned to the primary column's leading edge; the
        // Summary nav bar spans the secondary (right) column, so its midX sits well
        // to the right. Mirrors the sibling community-split test's midX technique.
        let primaryMidX = backButton.frame.midX
        let secondaryMidX = summaryNavBar.frame.midX
        XCTAssertLessThan(
            primaryMidX,
            secondaryMidX,
            "Primary column (midX \(primaryMidX)) should be left of secondary column (midX \(secondaryMidX))"
        )
    }
}
