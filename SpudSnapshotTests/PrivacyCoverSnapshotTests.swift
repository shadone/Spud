//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import UIKit
import XCTest
@testable import Spud

/// Snapshot of the privacy cover shown over NSFW content in the app-switcher
/// snapshot and during screen capture, in light and dark.
@MainActor
final class PrivacyCoverSnapshotTests: XCTestCase {
    private func traits(_ style: UIUserInterfaceStyle) -> UITraitCollection {
        UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: style),
            UITraitCollection(displayScale: 2),
        ])
    }

    func test_privacyCover_light() {
        assertCover(style: .light)
    }

    func test_privacyCover_dark() {
        assertCover(style: .dark)
    }

    private func assertCover(
        style: UIUserInterfaceStyle,
        testName: String = #function,
        line: UInt = #line
    ) {
        let size = CGSize(width: 390, height: 600)
        let view = PrivacyCoverView(frame: CGRect(origin: .zero, size: size))
        view.layoutIfNeeded()

        assertSnapshot(
            matching: view,
            as: .image(size: size, traits: traits(style)),
            named: style == .dark ? "dark" : "light",
            testName: testName,
            line: line
        )
    }
}
