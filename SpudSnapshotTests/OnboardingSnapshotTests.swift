//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import UIKit
import XCTest
@testable import Spud

/// Snapshots of the first-launch Welcome screen in light and dark, pinned to a
/// device config so the references are simulator-independent.
@MainActor
final class OnboardingSnapshotTests: XCTestCase {
    private let lemmyTeal = UIColor(red: 0, green: 0x96 / 255, blue: 0x87 / 255, alpha: 1)

    func test_welcome() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let viewController = OnboardingWelcomeViewController()
            viewController.view.tintColor = lemmyTeal
            assertSnapshot(
                matching: viewController,
                as: .image(on: .iPhone13Pro, traits: UITraitCollection(userInterfaceStyle: style)),
                named: style == .dark ? "dark" : "light"
            )
        }
    }
}
