//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SBTUITestTunnelClient
import XCTest

/// Verifies that attempting to log in to a non-Lemmy instance (e.g. PieFed)
/// is blocked before any network call, showing an action sheet titled
/// "<Software> isn't supported yet" with an "Open in Safari" button.
///
/// ## Seam strategy
///
/// The test pre-seeds the NodeInfo cache via `AppLaunchArgument.seedNonLemmyLoginForUITests`
/// (backed by `AppDatabase.seedNodeInfoCacheForUITests`), which makes
/// `NodeInfoService.detect(host:)` return `PlatformUnsupportedError` immediately.
/// The login screen is presented directly (no onboarding flow navigation) so
/// the test can type credentials and tap "Log in" without any fixture stubs
/// for the real Lemmy API endpoints. The catch-all 500 stub ensures that any
/// accidental network probe fails loudly rather than silently succeeding.
///
/// SpudUITests target stays at Swift 5 until SBTUITestTunnelClient supports
/// strict concurrency.
class NodeInfoBlockUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false

        // Device orientation is simulator-hardware state that survives
        // ResetFilesystem and can leak from an earlier suite run.
        XCUIDevice.shared.orientation = .portrait

        app = SBTUITunneledApplication()
        let launchOptions: [String] = [
            SBTUITunneledApplicationLaunchOptionResetFilesystem,
            SBTUITunneledApplicationLaunchOptionDisableUITextFieldAutocomplete,
            AppLaunchArgument.staticImageService.rawValue,
            // Wipe the App Group DB: it survives SBT's ResetFilesystem, so a
            // default account from an earlier suite would make the seam no-op.
            AppLaunchArgument.wipeAppDatabase.rawValue,
            // Present the login screen directly with a pre-seeded NodeInfo
            // cache record for a non-Lemmy host.
            AppLaunchArgument.seedNonLemmyLoginForUITests.rawValue,
        ]
        app.launchEnvironment["SPUDNonLemmyLoginHost"] = "piefed.social"
        app.launchTunnel(withOptions: launchOptions) {
            // Catch-all 500: any network probe that slips through fails loudly.
            _ = self.app.stubRequests(
                matching: SBTRequestMatch(url: ".*"),
                response: SBTStubResponse(response: "", returnCode: 500)
            )
        }
    }

    /// Tapping "Log in" on a PieFed instance shows "PieFed isn't supported yet"
    /// with an "Open in Safari" action and a "Cancel" button. No network call
    /// is needed — the NodeInfo cache short-circuits the preflight check.
    func test_nonLemmyLogin_showsBlockSheet() {
        let usernameField = app.textFields["login-username"]
        XCTAssertTrue(
            usernameField.waitForExistence(timeout: 10),
            "Login screen should appear via the non-Lemmy seed seam"
        )
        usernameField.tap()
        usernameField.typeText("testuser")

        let passwordField = app.secureTextFields["login-password"]
        XCTAssertTrue(passwordField.waitForExistence(timeout: 5))
        passwordField.tap()
        passwordField.typeText("password")

        let loginButton = app.buttons["login-submit"]
        XCTAssertTrue(loginButton.waitForExistence(timeout: 5))
        loginButton.tap()

        XCTAssertTrue(
            app.buttons["Open in Safari"].waitForExistence(timeout: 5),
            "Block sheet should appear with an 'Open in Safari' button"
        )
        XCTAssertTrue(
            app.staticTexts
                .matching(NSPredicate(format: "label CONTAINS %@", "isn't supported yet"))
                .firstMatch
                .exists,
            "Block sheet should display '<Software> isn\u{2019}t supported yet'"
        )
        XCTAssertTrue(
            app.buttons["Cancel"].exists,
            "Block sheet should have a Cancel button"
        )
    }
}
