//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import UIKit
import XCTest
@testable import Spud

@MainActor
final class ActivityFootprintRailSnapshotTests: XCTestCase {
    private func makeRail() -> ActivityFootprintRailView {
        let rail = ActivityFootprintRailView()
        rail.configure(
            stats: [
                .init(value: "128", label: "Posts"),
                .init(value: "1.2k", label: "Comments"),
                .init(value: "342", label: "Saved"),
                .init(value: "5.0k", label: "Votes"),
            ],
            accent: UIColor(red: 0, green: 0.59, blue: 0.53, alpha: 1) // Lemmy teal
        )
        rail.frame = CGRect(x: 0, y: 0, width: 390, height: 84)
        return rail
    }

    func test_footprintRail_light() {
        let rail = makeRail()
        assertSnapshot(of: rail, as: .image(traits: .init(userInterfaceStyle: .light)), named: "light")
    }

    func test_footprintRail_dark() {
        let rail = makeRail()
        assertSnapshot(of: rail, as: .image(traits: .init(userInterfaceStyle: .dark)), named: "dark")
    }
}
