//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import SwiftUI
import UIKit
import XCTest
@testable import Spud

/// Screen snapshot of the `MetaCommunityBadge` pill in isolation, light and
/// dark. Confirms the badge (SF Symbol + tinted capsule) renders legibly on
/// its own, independent of any host row.
///
/// As an `.image(size:traits:)` snapshot this is device- and runtime-sensitive;
/// record on the reference iPhone 17 Pro, iOS 26.3. `contentSizeTrait` pins
/// Dynamic Type to the recorded default so the sim's persisted content-size
/// setting can't drift the text metrics.
@MainActor
final class MetaCommunityBadgeSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        SnapshotDeterminism.pinAccent()
        SnapshotDeterminism.pinStatusBarHidden()
    }

    func test_badge() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let size = CGSize(width: 120, height: 60)
            let view = MetaCommunityBadge()
                .padding()
                .frame(width: size.width, height: size.height)
                .background(Color(uiColor: .systemBackground))

            let host = UIHostingController(rootView: view)
            host.view.frame = CGRect(origin: .zero, size: size)
            host.view.layoutIfNeeded()

            assertSnapshot(
                matching: host,
                as: .image(size: size, traits: UITraitCollection(traitsFrom: [
                    UITraitCollection(userInterfaceStyle: style),
                    SnapshotDeterminism.contentSizeTrait,
                ])),
                named: style == .dark ? "dark" : "light"
            )
        }
    }
}
