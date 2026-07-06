//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SBTUITestTunnelClient
import UIKit
import XCTest

/// iPhone signed-in UITest that exercises the optimistic vote path end-to-end
/// through the POST-DETAIL HEADER: opening a feed post into PostDetail and
/// tapping the header's upvote button applies the vote LOCALLY and INSTANTLY
/// (score + vote state), and the sign-in gate the same tap raises while signed
/// OUT never appears.
///
/// ## Why this is the seam's proof
///
/// This branch re-plumbed PostDetail's data flow so the header cell renders from
/// a VM-owned observation, and Phase 1 folded the post-level vote into
/// `PostSaveDispatching`. Tapping the header upvote enqueues an optimistic outbox
/// write; the DB row updates (score +1, vote -> up) and flows back through the
/// header's observation, which reconfigures the cell in place. This test lands
/// the app already authenticated via
/// `AppLaunchArgument.seedSignedInDefaultAccount` (a local person row + fake JWT
/// on discuss.tchncs.de), so the tap takes the signed-in branch — the optimistic
/// header change is the positive proof, the absent gate the negative one.
///
/// ## Which score the header shows
///
/// The feed fixture (`post-list-all-hot.json`) and the detail fixture
/// (`post-detail-1549703.json`) carry DIFFERENT scores for the same post (1276
/// vs 2247). Tapping a feed cell whose row already exists in the DB routes
/// straight to `PostDetailViewController` (not the loading VC), and the content
/// VC's initial load fetches only comments — `getPost` (`fetchPostInfo`) fires
/// only on pull-to-refresh, and the comment fetch carries no post counters. So
/// the header renders the FEED-import score, 1276, on open; the detail fixture's
/// 2247 would only land after an explicit pull-to-refresh, which this test does
/// not perform. The test waits for "1276 points" before tapping, then asserts
/// the optimistic 1276 -> 1277 (and vote -> upvoted).
///
/// ## Why the catch-all 500 is safe
///
/// The optimistic write applies synchronously inside the outbox enqueue and
/// flows back through the header observation; the network send is retried in the
/// BACKGROUND, so the catch-all 500 stub cannot destabilise the on-screen
/// result. That background-retry independence is exactly what this test pins —
/// the vote endpoint is deliberately NOT stubbed 200.
///
/// ## Why the App Group wipe
///
/// The signed-in seed no-ops if a default account already exists, and the App
/// Group `AppDatabase` survives SBT's `ResetFilesystem` and `simctl uninstall`,
/// so a persisted account from an earlier suite on the shared sim would silently
/// make the seed no-op and land the Posts tab on the signed-out feed (no
/// optimistic vote). Passing `AppLaunchArgument.wipeAppDatabase` deletes the
/// store before it opens, making this test order-independent.
///
/// SpudUITests target stays at Swift 5 until SBTUITestTunnelClient supports
/// strict concurrency.
class PostDetailVoteUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false

        // Device orientation is simulator-hardware state, not app data: it
        // survives ResetFilesystem and can leak in from a DIFFERENT UITest
        // class (or an interrupted prior run) that left the simulator in
        // landscape. Pin portrait explicitly so the feed cell and header
        // button are discoverable within this test's timeouts.
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

            // getPost for the opened post. On open from a feed cell whose row
            // already exists this does NOT fire (only pull-to-refresh calls it),
            // so it is defensive parity with the signed-out detail suite.
            _ = self.app.stubRequests(
                matching: SBTRequestMatch(
                    url: "discuss.tchncs.de/api/v3/post",
                    query: ["id=1549703"],
                    method: "GET"
                ),
                response: SBTStubResponse(fileNamed: "post-detail-1549703.json")
            )

            // Comments for the opened post — fetched on the content VC's initial
            // load. Carries no post counters, so it does not change the header
            // score.
            _ = self.app.stubRequests(
                matching: SBTRequestMatch(
                    url: "discuss.tchncs.de/api/v3/comment/list",
                    query: ["post_id=1549703", "max_depth=8", "sort=Hot"],
                    method: "GET"
                ),
                response: SBTStubResponse(fileNamed: "comment-list-1549703-Hot.json")
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

    /// Opening the fixture's first post into PostDetail and tapping the HEADER's
    /// upvote arrow applies the vote optimistically (score 1276 -> 1277, state ->
    /// upvoted) with no sign-in gate. The header score is asserted via the
    /// subtitle score label's accessibility label, which spells the score in full
    /// ("1276 points") — the visible label abbreviates 1276 and 1277 identically
    /// to "1.3K", so only the a11y label shows the +1. The optimistic change is
    /// the positive seam proof; the absent "Sign in to vote" gate the negative
    /// one.
    func test_headerUpvote_appliesOptimisticallyAndShowsNoGate() {
        let firstCell = app.cell(containing: "Nunc scelerisque tortor eget ligula pretium tempor")
        XCTAssertTrue(
            firstCell.waitForExistence(timeout: 15),
            "Signed-in feed should load the seeded All/Hot fixture"
        )
        firstCell.tap()

        // The post-detail header cell (`accessibilityIdentifier = postDetailHeader`).
        let header = app.cells["postDetailHeader"]
        XCTAssertTrue(
            header.waitForExistence(timeout: 15),
            "Tapping the post should push PostDetail with its header"
        )

        // The header's score is the only static text spelling "points"
        // (`subtitleScoreLabel.accessibilityLabel`, from
        // `VoteAccessibility.scoreLabel`). Match on the stable "points" substring
        // so the same element handle survives the score changing on the vote.
        let scoreLabel = header.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "points"))
            .firstMatch

        // Baseline: the header renders the FEED-import score 1276 (getPost fires
        // only on pull-to-refresh, which this test doesn't do), and the post
        // starts un-voted.
        let baselineLoaded = expectation(
            for: NSPredicate(format: "label CONTAINS %@", "1276 points"),
            evaluatedWith: scoreLabel
        )
        wait(for: [baselineLoaded], timeout: 10)
        XCTAssertFalse(
            scoreLabel.label.contains("upvoted"),
            "Post should start un-voted, got: \(scoreLabel.label)"
        )

        // Tap the header's upvote button. Its accessibility label is state-aware
        // ("Upvote" while un-voted, from `VoteAccessibility.upvoteButtonLabel`),
        // and it lives in the header cell so a comment's upvote can't be hit.
        let upvoteButton = header.buttons["Upvote"]
        XCTAssertTrue(
            upvoteButton.waitForExistence(timeout: 5),
            "The header upvote button should be visible"
        )
        upvoteButton.tap()

        // Optimistic result: score 1276 -> 1277 and the vote reads "upvoted",
        // applied synchronously from the local write and flowed back through the
        // header observation. No network is needed — the catch-all 500 only fails
        // the background outbox send, which the optimistic UI must survive.
        let optimisticallyUpvoted = expectation(
            for: NSPredicate(
                format: "label CONTAINS %@ AND label CONTAINS %@",
                "1277 points",
                "upvoted"
            ),
            evaluatedWith: scoreLabel
        )
        wait(for: [optimisticallyUpvoted], timeout: 5)

        // The header's upvote button flips to its already-upvoted label,
        // confirming the header reconfigured from the optimistic state (not just
        // the pre-paint on tap).
        XCTAssertTrue(
            header.buttons["Remove upvote"].waitForExistence(timeout: 5),
            "The header upvote button should read as already-upvoted after the vote"
        )

        // Seam proof (negative): the sign-in gate the SAME tap raises while signed
        // out must not appear. "Sign in to vote" is the gate's title label.
        XCTAssertFalse(
            app.staticTexts["Sign in to vote"].waitForExistence(timeout: 2),
            "A signed-in vote must not present the sign-in gate"
        )
    }
}
