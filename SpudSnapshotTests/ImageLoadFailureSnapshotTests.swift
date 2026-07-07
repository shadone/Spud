//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import UIKit
import XCTest
@testable import Spud

/// Renders the post-detail image-load failure "Plate" to images so its layout
/// can be reviewed and regressions caught: the default failure state (glyph,
/// message, Retry + Open in browser) and the retrying state (activity indicator
/// + "Loading image…"), each in light and dark.
///
/// Everything renders at a fixed size and pinned display scale, so these
/// references are device-independent (like the media-thumbnail snapshots).
/// `tintColor` is pinned to the brand "Lemmy" teal — at runtime the actions
/// follow the user's accent (the window `tintColor`), which defaults to it.
@MainActor
final class ImageLoadFailureSnapshotTests: XCTestCase {
    private let lemmyTeal = UIColor(red: 0, green: 0x96 / 255, blue: 0x87 / 255, alpha: 1)

    private func traits(_ style: UIUserInterfaceStyle) -> UITraitCollection {
        UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: style),
            UITraitCollection(displayScale: 2),
            SnapshotDeterminism.contentSizeTrait,
        ])
    }

    private func plate(retrying: Bool) -> ImageLoadFailureView {
        let view = ImageLoadFailureView()
        view.tintColor = lemmyTeal
        view.setRetrying(retrying)
        return view
    }

    private func assertPlate(
        retrying: Bool,
        style: UIUserInterfaceStyle,
        testName: String = #function,
        line: UInt = #line
    ) {
        assertSnapshot(
            matching: plate(retrying: retrying),
            as: .image(
                size: CGSize(width: 390, height: ImageLoadFailureView.minimumHeight),
                traits: traits(style)
            ),
            testName: testName,
            line: line
        )
    }

    func test_failure_light() {
        assertPlate(retrying: false, style: .light)
    }

    func test_failure_dark() {
        assertPlate(retrying: false, style: .dark)
    }

    func test_retrying_light() {
        assertPlate(retrying: true, style: .light)
    }

    func test_retrying_dark() {
        assertPlate(retrying: true, style: .dark)
    }
}
