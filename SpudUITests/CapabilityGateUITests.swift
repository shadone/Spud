//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SBTUITestTunnelClient
import XCTest

/// End-to-end regression guard that the capability gating has been RETIRED for
/// the inbox: a stubbed `getSite` reporting Lemmy version "1.0.0" flows through
/// site import -> `SiteRecord.version` -> `InstanceCapabilities` -> the Inbox
/// tab, which now resolves `.can(.inbox) == true` (Spud speaks native v4), so the
/// gated `UIContentUnavailableConfiguration` must NOT appear.
///
/// ## Why this proves the whole chain, not just the UI
///
/// Unlike `InboxViewModelGatingTests` (a unit test that constructs
/// `InstanceCapabilities` directly), this test never touches
/// `InstanceCapabilities` or `AccountScope` - it only stubs the network
/// response for `GET /api/v3/site` and drives the real app. The gated title
/// staying absent, even after that stub is imported, exercises the full chain:
/// the stub decoded (every required `GetSiteResponse` field is present - the
/// fixture is derived from the same shape as `GetSiteResponse+fake.swift`, with
/// only `version` changed to "1.0.0"), `SiteImporter.upsertSite` wrote
/// `SiteRecord.version`, `AccountService.instanceCapabilities` parsed it into a
/// Lemmy 1.x `LemmyVersion`, and `InboxViewModel.loadAll()` read `.can(.inbox) ==
/// true` from the live `AccountScope` — proving the version table no longer
/// gates.
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

    /// A Lemmy 1.0 home instance NO LONGER gates the Inbox tab: now that Spud
    /// speaks native v4, the previously-gated inbox is available, so the
    /// "Inbox isn't available yet" explain-don't-hide title must never appear —
    /// even after the stubbed 1.0.0 `getSite` version is imported.
    ///
    /// This is the end-to-end regression guard against re-introducing the gate:
    /// the same chain the old test relied on (getSite -> SiteRecord.version ->
    /// InstanceCapabilities -> InboxViewModel.loadAll) now resolves to
    /// `.can(.inbox) == true`, so the inbox loads its normal content/error state
    /// (the v4 notification fetch hits the catch-all 500 stub) rather than the
    /// gated title.
    func test_inboxNotGated_onLemmy1_0Instance() {
        let postsTab = app.buttons["Posts"].firstMatch
        XCTAssertTrue(postsTab.waitForExistence(timeout: 15), "App should land signed-in on the Posts tab")

        let inboxTab = app.buttons["Inbox"].firstMatch
        XCTAssertTrue(inboxTab.waitForExistence(timeout: 5), "Inbox tab should be reachable")

        // Query any element type (not just staticTexts): `UIContentUnavailableView`
        // is a system view whose exact accessibility-tree shape (single label vs.
        // a grouped title+message element) isn't something to hard-code.
        let gatedTitle = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Inbox isn't available yet"))
            .firstMatch

        // Give the scheduler's background `getSite` fetch (which imports the
        // stubbed "1.0.0" version) ample time to land — it fires asynchronously
        // ~10s after launch — while repeatedly returning to the Inbox tab so each
        // `viewWillAppear` re-reads capabilities live. The gated title must never
        // appear across the whole window.
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            inboxTab.tap()
            XCTAssertFalse(
                gatedTitle.waitForExistence(timeout: 3),
                "Inbox must not gate on a Lemmy 1.0 instance now that Spud speaks native v4"
            )
            postsTab.tap()
        }
    }
}
