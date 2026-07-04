//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import SpudUtilKit
import UIKit
import XCTest
@testable import Spud

/// Snapshots of the two-factor (TOTP) code-entry screen in light and dark,
/// pinned to a device config so the references are simulator-independent. The
/// code is pre-filled with "419" and the active-cell state forced (mirroring the
/// `LoginTwoFactor` design mockup) so the references show a partially-entered
/// code with the accent active-cell border and caret.
@MainActor
final class LoginTwoFactorSnapshotTests: XCTestCase {
    private let lemmyTeal = UIColor(red: 0, green: 0x96 / 255, blue: 0x87 / 255, alpha: 1)

    func test_twoFactor() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let viewController = LoginTwoFactorViewController(
                username: "spud_fan",
                hostname: "lemmy.world",
                onSubmit: { _ in }
            )
            viewController.view.tintColor = lemmyTeal
            // Force layout, then pre-fill the partial code with the active cell
            // visible so the references show the accent border + caret.
            viewController.view.setNeedsLayout()
            viewController.view.layoutIfNeeded()
            viewController.setCodeForTesting("419", activeCellVisible: true)

            let navigationController = UINavigationController(rootViewController: viewController)
            navigationController.view.tintColor = lemmyTeal
            assertSnapshot(
                matching: navigationController,
                as: .image(on: .deterministicPhone, traits: UITraitCollection(userInterfaceStyle: style)),
                named: style == .dark ? "dark" : "light"
            )
        }
    }
}
