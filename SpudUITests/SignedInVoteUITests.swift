//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SBTUITestTunnelClient
import UIKit
import XCTest

/// iPhone signed-in UITest that exercises the optimistic vote path end-to-end
/// through the new signed-in seed: tapping a feed cell's inline upvote arrow
/// applies the vote LOCALLY and INSTANTLY (score + vote state), and the sign-in
/// gate the same tap raises while signed OUT never appears.
///
/// ## Why this is the seam's proof
///
/// `PostActionDispatching.vote` gates on `accountScope.isSignedOut`: signed out it
/// presents the "Sign in to vote" gate and returns; signed in it enqueues an
/// optimistic outbox write. This test lands the app already authenticated via
/// `AppLaunchArgument.seedSignedInDefaultAccount` (a local person row + fake JWT on
/// discuss.tchncs.de), so the tap must take the signed-in branch — the optimistic
/// UI change is the positive proof, the absent gate the negative one.
///
/// ## Why the catch-all 500 is safe
///
/// The optimistic write applies synchronously inside the outbox enqueue (score
/// 1276 -> 1277, vote neutral -> up on the fixture's first post) and flows back
/// through the row observation; the network send is retried in the BACKGROUND, so
/// the catch-all 500 stub cannot destabilise the on-screen result. That
/// background-retry independence is exactly what this test pins — the vote
/// endpoint is deliberately NOT stubbed 200.
///
/// ## Why the App Group wipe
///
/// The signed-in seed no-ops if a default account already exists, and the App
/// Group `AppDatabase` survives SBT's `ResetFilesystem` and `simctl uninstall`, so
/// a persisted account from an earlier suite on the shared sim would silently make
/// the seed no-op and land the Posts tab on the signed-out feed (no optimistic
/// vote). Passing `AppLaunchArgument.wipeAppDatabase` deletes the store before it
/// opens, making this test order-independent.
///
/// SpudUITests target stays at Swift 5 until SBTUITestTunnelClient supports strict
/// concurrency.
class SignedInVoteUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false

        // Device orientation is simulator-hardware state, not app data: it
        // survives ResetFilesystem and can leak in from a DIFFERENT UITest
        // class (or an interrupted prior run) that left the simulator in
        // landscape without resetting it. In landscape the inline vote
        // arrows are not discoverable within this test's timeouts, so pin
        // portrait explicitly rather than assume it (mirrors the reset
        // `SpudUITests.tearDownWithError` does for its own rotation test).
        XCUIDevice.shared.orientation = .portrait

        app = SBTUITunneledApplication()
        let launchOptions: [String] = [
            SBTUITunneledApplicationLaunchOptionResetFilesystem,
            SBTUITunneledApplicationLaunchOptionDisableUITextFieldAutocomplete,
            AppLaunchArgument.staticImageService.rawValue,
            // Delete the App Group AppDatabase before it opens: it survives SBT's
            // ResetFilesystem and `simctl uninstall`, so a default account left by
            // an earlier suite would make the signed-in seed below no-op and land
            // the Posts tab on the signed-out feed (no optimistic vote). The wipe
            // makes this test order-independent.
            AppLaunchArgument.wipeAppDatabase.rawValue,
            // Land already authenticated (local person row + fake JWT on
            // discuss.tchncs.de) so the vote takes the signed-in branch.
            // Deliberately NOT the signed-out seed — that would present the
            // sign-in gate on the tap.
            AppLaunchArgument.seedSignedInDefaultAccount.rawValue,
        ]
        app.launchTunnel(withOptions: launchOptions) {
            self.app.monitorRequests(matching: SBTRequestMatch(url: ".*"))

            // Catch-all 500 FIRST: any endpoint not explicitly stubbed below
            // (including the vote's background outbox send) fails, which the
            // optimistic UI must survive.
            _ = self.app.stubRequests(
                matching: SBTRequestMatch(url: ".*"),
                response: SBTStubResponse(response: "", returnCode: 500)
            )

            _ = self.app.stubRequests(
                matching: SBTRequestMatch(
                    url: "https://.*/pictrs/image/.*",
                    method: "GET"
                ),
                response: SBTStubResponse(
                    response: [
                        "image": "tv-pattern",
                    ],
                    contentType: "application/vnd.info.ddenis.spud.image+json"
                )
            )

            // The seeded signed-in account's default frontpage feed is All/Hot
            // (no getSite ran, so no server override — defaultListingType falls
            // back to .All), matching this stub. Same fixture the signed-out
            // iPhone suite (`SpudUITests`) uses.
            _ = self.app.stubRequests(
                matching: SBTRequestMatch(
                    url: "discuss.tchncs.de/api/v3/post/list",
                    query: ["type_=All", "sort=Hot"],
                    method: "GET"
                ),
                response: SBTStubResponse(fileNamed: "post-list-all-hot.json")
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

    /// Tapping a signed-in feed cell's inline upvote arrow applies the vote
    /// optimistically (score 1276 -> 1277, state -> upvoted on the fixture's first
    /// post) with no sign-in gate. The score is asserted via the subtitle's
    /// accessibility label, which spells the score in full — the visible label
    /// abbreviates 1276 and 1277 identically to "1.3K", so only the a11y label
    /// shows the +1. The optimistic change is the positive seam proof; the absent
    /// "Sign in to vote" gate the negative one.
    func test_upvote_appliesOptimisticallyAndShowsNoGate() {
        let firstCell = app.cell(containing: "Nunc scelerisque tortor eget ligula pretium tempor")
        XCTAssertTrue(
            firstCell.waitForExistence(timeout: 15),
            "Signed-in feed should load the seeded All/Hot fixture"
        )

        // Baseline: the fixture's first post has score 1276 and no vote. The
        // "subtitle" element's accessibility label is `subtitleAccessibilityLabel`
        // ("<community>, <score> points[, upvoted], <comments>, <age>").
        let subtitle = firstCell.staticTexts["subtitle"]
        XCTAssertTrue(subtitle.waitForExistence(timeout: 5), "Post cell should expose its subtitle")
        XCTAssertTrue(
            subtitle.label.contains("1276 points"),
            "Baseline subtitle should show the fixture score 1276, got: \(subtitle.label)"
        )
        XCTAssertFalse(
            subtitle.label.contains("upvoted"),
            "Post should start un-voted, got: \(subtitle.label)"
        )

        // Tap the trailing inline upvote arrow (accessibilityLabel "Upvote"),
        // scoped to the first cell so the second post's arrow can't be hit.
        let upvoteButton = firstCell.buttons["Upvote"]
        XCTAssertTrue(
            upvoteButton.waitForExistence(timeout: 5),
            "The inline upvote arrow should be visible (vote buttons are on by default)"
        )
        upvoteButton.tap()

        // Optimistic result: score 1276 -> 1277 and the vote reads "upvoted",
        // applied synchronously from the local write and flowed back through the
        // row observation. No network is needed — the catch-all 500 only fails the
        // background outbox send, which the optimistic UI must survive.
        let optimisticallyUpvoted = expectation(
            for: NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "1277 points", "upvoted"),
            evaluatedWith: subtitle
        )
        wait(for: [optimisticallyUpvoted], timeout: 5)

        // Seam proof (negative): the sign-in gate the SAME tap raises while signed
        // out must not appear. "Sign in to vote" is the gate's title label.
        XCTAssertFalse(
            app.staticTexts["Sign in to vote"].waitForExistence(timeout: 2),
            "A signed-in vote must not present the sign-in gate"
        )
    }
}
