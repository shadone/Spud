//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SBTUITestTunnelClient
import XCTest

/// End-to-end regression coverage for the capability-gating chain built on
/// this branch: a stubbed `getSite` reporting Lemmy version "1.0.0" flows
/// through site import -> `SiteRecord.version` -> `InstanceCapabilities` ->
/// the Inbox tab's gated `UIContentUnavailableConfiguration` (Task 7).
///
/// ## Why this proves the whole chain, not just the UI
///
/// Unlike `InboxViewModelGatingTests` (a unit test that constructs
/// `InstanceCapabilities` directly), this test never touches
/// `InstanceCapabilities` or `AccountScope` - it only stubs the network
/// response for `GET /api/v3/site` and drives the real app. The gated title
/// appearing is only possible if: the stub decoded (every required
/// `GetSiteResponse` field is present - the fixture is derived from the same
/// shape as `GetSiteResponse+fake.swift`, with only `version` changed to
/// "1.0.0"), `SiteImporter.upsertSite` wrote `SiteRecord.version`,
/// `AccountService.instanceCapabilities` parsed it into a Lemmy 1.x
/// `LemmyVersion`, and `InboxViewModel.loadAll()` read `.can(.inbox) ==
/// false` from the live `AccountScope`.
///
/// ## Timing
///
/// The signed-in seed lands on a brand-new account, so
/// `SchedulerService.startService()`'s "fetch initial site info for accounts
/// awaiting MyUserInfo" sweep is what actually calls `getSite`. In practice
/// this fires almost immediately: `ReachabilityMonitor`'s `statusStream`
/// replays its current value (`true`, assumed online at construction) to the
/// scheduler's subscriber right away, which reads as "just came online" and
/// triggers an immediate `tick()` - well before the belt-and-suspenders 10s
/// `DispatchQueue.main.asyncAfter` timer fire. Either way,
/// `InboxViewModel.loadAll()` only re-reads capabilities when it runs again
/// (`viewDidLoad`, `viewWillAppear`, or pull-to-refresh) - it does not
/// observe the import happening in the background. So the test polls by
/// repeatedly leaving and returning to the Inbox tab - each return fires
/// `viewWillAppear` -> `loadAll()` - until the gated title appears, which
/// tolerates either path without hard-coding which one wins.
///
/// SpudUITests target stays at Swift 5 until SBTUITestTunnelClient supports
/// strict concurrency.
class CapabilityGateUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false

        // Device orientation is simulator-hardware state, not app data: it
        // survives ResetFilesystem and can leak in from a different UITest
        // class (or an interrupted prior run) that left the simulator in
        // landscape without resetting it.
        XCUIDevice.shared.orientation = .portrait

        app = SBTUITunneledApplication()
        let launchOptions: [String] = [
            SBTUITunneledApplicationLaunchOptionResetFilesystem,
            SBTUITunneledApplicationLaunchOptionDisableUITextFieldAutocomplete,
            AppLaunchArgument.staticImageService.rawValue,
            // Delete the App Group AppDatabase before it opens: it survives SBT's
            // ResetFilesystem and `simctl uninstall`, so a default account left by
            // an earlier suite would make the signed-in seed below no-op - this
            // test needs a BRAND NEW account (never fetched site info) so the
            // scheduler's "awaiting MyUserInfo" sweep is the one that calls
            // getSite.
            AppLaunchArgument.wipeAppDatabase.rawValue,
            // Land already authenticated on discuss.tchncs.de (fixed keychain id,
            // fake JWT) so the Inbox tab's `isSignedIn` branch is exercised.
            AppLaunchArgument.seedSignedInDefaultAccount.rawValue,
        ]
        app.launchTunnel(withOptions: launchOptions) {
            self.app.monitorRequests(matching: SBTRequestMatch(url: ".*"))

            // Catch-all 500 FIRST: any endpoint not explicitly stubbed below
            // (the Posts feed, the outbox drain, etc.) fails loudly. This test
            // only cares about the getSite response driving capability gating.
            _ = self.app.stubRequests(
                matching: SBTRequestMatch(url: ".*"),
                response: SBTStubResponse(response: "", returnCode: 500)
            )

            // The version-gating seam under test: a Lemmy 1.0.0 `getSite`
            // response. `$` anchors past `/api/v3/site` so this doesn't also
            // catch `/api/v3/site/block`.
            _ = self.app.stubRequests(
                matching: SBTRequestMatch(
                    url: "discuss.tchncs.de/api/v3/site$",
                    method: "GET"
                ),
                response: SBTStubResponse(fileNamed: "site-1.0.0.json")
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

    /// A Lemmy 1.0 home instance gates the Inbox tab: the tab stays reachable
    /// but shows "Inbox isn't available yet" (Task 7's explain-don't-hide
    /// design) instead of replies/mentions/messages, and the compose button
    /// (only ever shown ungated, in the Messages scope) never appears.
    func test_gatedInbox_onLemmy1_0Instance() {
        let postsTab = app.buttons["Posts"].firstMatch
        XCTAssertTrue(postsTab.waitForExistence(timeout: 15), "App should land signed-in on the Posts tab")

        let inboxTab = app.buttons["Inbox"].firstMatch
        XCTAssertTrue(inboxTab.waitForExistence(timeout: 5), "Inbox tab should be reachable even when gated")

        // Query any element type (not just staticTexts): `UIContentUnavailableView`
        // is a system view whose exact accessibility-tree shape (single label vs.
        // a grouped title+message element) isn't something to hard-code.
        let gatedTitle = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Inbox isn't available yet"))
            .firstMatch

        // Poll by leaving and returning to the Inbox tab: each return fires
        // `viewWillAppear` -> `InboxViewModel.loadAll()`, which re-reads
        // capabilities live. The scheduler's background `getSite` fetch (which
        // imports the stubbed "1.0.0" version) lands asynchronously ~10s after
        // launch, so a single tap right after launch can race it - retrying for
        // up to 30s comfortably covers that delay without a blind sleep.
        var gated = false
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            inboxTab.tap()
            if gatedTitle.waitForExistence(timeout: 3) {
                gated = true
                break
            }
            postsTab.tap()
        }
        XCTAssertTrue(
            gated,
            "Inbox should show the capability-gate title once the stubbed 1.0.0 getSite response is imported"
        )

        XCTAssertFalse(
            app.buttons["New message"].exists,
            "The compose button must not appear while the Inbox is gated"
        )
    }
}
