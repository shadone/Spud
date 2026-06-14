//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import SpudDataKit
import UIKit
import XCTest
@testable import Spud

/// Snapshots of the signed-out authentication surfaces: the `SignInGate` sheet
/// (one per write action — vote / comment / save / subscribe), the signed-out
/// Account screen, and the pinned account-actions footer — each in light and
/// dark.
///
/// The two view controllers render at a pinned `ViewImageConfig` (iPhone 13 Pro
/// size/scale/safe-area) and the footer at a fixed width with a measured natural
/// height, so the references are device-independent — they record and verify
/// identically on any simulator. None of these surfaces load images or touch the
/// database, so the snapshots are deterministic with no async settling. The
/// brand "Lemmy" teal is pinned on each root so the accent-tinted controls match
/// the runtime window `tintColor` (which defaults to it).
@MainActor
final class AuthScreensSnapshotTests: XCTestCase {
    private let lemmyTeal = UIColor(red: 0, green: 0x96 / 255, blue: 0x87 / 255, alpha: 1)
    private let width: CGFloat = 390

    private func traits(_ style: UIUserInterfaceStyle) -> UITraitCollection {
        UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: style),
            UITraitCollection(displayScale: 2),
        ])
    }

    // MARK: - SignInGate

    private func assertSignInGate(
        title: String,
        testName: String = #function,
        line: UInt = #line
    ) {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let viewController = SignInGateViewController(title: title, onSignIn: { })
            // Pin the accent on the snapshot root: the `.image` strategy reparents
            // the view into a fresh window, so without its own tintColor the
            // neutral / plain buttons would inherit system blue instead of the
            // brand teal the runtime window applies. The accent ring and filled
            // button read `ThemeManager.currentAccentColor` directly (already the
            // brand teal), so they stay consistent.
            viewController.view.tintColor = lemmyTeal
            assertSnapshot(
                matching: viewController,
                as: .image(on: .iPhone13Pro, traits: traits(style)),
                named: style == .dark ? "dark" : "light",
                testName: testName,
                line: line
            )
        }
    }

    func test_signInGate_vote() {
        assertSignInGate(title: NSLocalizedString("Sign in to vote", comment: ""))
    }

    func test_signInGate_comment() {
        assertSignInGate(title: NSLocalizedString("Sign in to comment", comment: ""))
    }

    func test_signInGate_save() {
        assertSignInGate(title: NSLocalizedString("Sign in to save", comment: ""))
    }

    func test_signInGate_subscribe() {
        assertSignInGate(title: NSLocalizedString("Sign in to subscribe", comment: ""))
    }

    // MARK: - AccountSignedOut

    func test_accountSignedOut() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let viewController = AccountSignedOutViewController()
            viewController.view.tintColor = lemmyTeal
            assertSnapshot(
                matching: viewController,
                as: .image(on: .iPhone13Pro, traits: traits(style)),
                named: style == .dark ? "dark" : "light"
            )
        }
    }

    // MARK: - AccountActionsFooterView

    func test_accountActionsFooter() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let view = AccountActionsFooterView()
            view.tintColor = lemmyTeal
            let height = view.systemLayoutSizeFitting(
                CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            ).height
            assertSnapshot(
                matching: view,
                as: .image(size: CGSize(width: width, height: height), traits: traits(style)),
                named: style == .dark ? "dark" : "light"
            )
        }
    }
}
