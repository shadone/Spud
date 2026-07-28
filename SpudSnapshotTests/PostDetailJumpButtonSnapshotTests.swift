//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import SpudUIKit
import UIKit
import XCTest
@testable import Spud

/// Visual coverage for the post-detail jump FAB's two states — the default
/// next-top-level chevron and the prominent "Next new" capsule.
///
/// The control had none until now, which is how its Liquid Glass conversion
/// shipped an illegible "Next new" label. These references are the *shape*
/// record; legibility itself is asserted numerically in
/// `SpudTests/PostDetailJumpButtonContrastTests` — a snapshot cannot catch a
/// contrast regression, because an illegible reference is still a stable one.
///
/// Captured **on-screen** (`drawHierarchyInKeyWindow: true`): the default
/// offscreen `layer.render(in:)` strategy does not composite Liquid Glass at
/// all, so an offscreen reference of a glass control records the material as
/// absent and can never regress.
@MainActor
final class PostDetailJumpButtonSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // The host app's launch tint leaks into on-screen captures; pin it so
        // the reference does not depend on the sim's persisted accent.
        SnapshotDeterminism.pinAccent()
        SnapshotDeterminism.pinStatusBarHidden()
    }

    /// No new comments: the non-prominent glass chevron.
    func test_jumpButton_default() {
        assertBothAppearances(isNew: false)
    }

    /// New comments below the fold: the prominent "Next new" capsule.
    func test_jumpButton_nextNew() {
        assertBothAppearances(isNew: true)
    }

    // MARK: - Helpers

    private func assertBothAppearances(
        isNew: Bool,
        testName: String = #function,
        line: UInt = #line
    ) {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let host = makeHost(isNew: isNew)
            assertSnapshot(
                matching: host,
                as: .image(
                    drawHierarchyInKeyWindow: true,
                    size: host.bounds.size,
                    traits: traits(style)
                ),
                named: style == .dark ? "dark" : "light",
                testName: testName,
                line: line
            )
        }
    }

    /// The FAB floats over the comment list, so it is captured on the same
    /// `.systemBackground` it sits on there.
    private func makeHost(isNew: Bool) -> UIView {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 240, height: 76))
        host.backgroundColor = .systemBackground
        host.tintColor = ThemeManager.currentAccentColor

        let button = UIButton(configuration: JumpButtonStyle.configuration(isNew: isNew))
        button.accessibilityLabel = JumpButtonStyle.accessibilityLabel(isNew: isNew)
        button.sizeToFit()
        button.frame = CGRect(
            x: (host.bounds.width - button.bounds.width) / 2,
            y: (host.bounds.height - button.bounds.height) / 2,
            width: button.bounds.width,
            height: button.bounds.height
        )
        host.addSubview(button)
        host.layoutIfNeeded()
        return host
    }

    private func traits(_ style: UIUserInterfaceStyle) -> UITraitCollection {
        UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: style),
            UITraitCollection(displayScale: 2),
            SnapshotDeterminism.contentSizeTrait,
        ])
    }
}
