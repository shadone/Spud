//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import UIKit
import XCTest
@testable import Spud

/// Snapshot of the "Open in Spud" search row across kinds, in light and dark.
@MainActor
final class SearchOpenURLCellSnapshotTests: XCTestCase {
    private let lemmyTeal = UIColor(red: 0, green: 0x96 / 255, blue: 0x87 / 255, alpha: 1)
    private let width: CGFloat = 390

    func test_post() {
        let cell = SearchOpenURLCell(style: .subtitle, reuseIdentifier: nil)
        cell.configure(kind: .post, displayURL: "lemmy.world/post/123456")
        assertCell(cell)
    }

    func test_community() {
        let cell = SearchOpenURLCell(style: .subtitle, reuseIdentifier: nil)
        cell.configure(kind: .community, displayURL: "lemmy.world/c/asklemmy")
        assertCell(cell)
    }

    func test_instance() {
        let cell = SearchOpenURLCell(style: .subtitle, reuseIdentifier: nil)
        cell.configure(kind: .instance, displayURL: "lemmy.world")
        assertCell(cell)
    }

    private func assertCell(
        _ cell: UITableViewCell,
        testName: String = #function,
        line: UInt = #line
    ) {
        cell.tintColor = lemmyTeal
        cell.contentView.tintColor = lemmyTeal
        cell.contentView.backgroundColor = .systemBackground
        for style in [UIUserInterfaceStyle.light, .dark] {
            cell.frame = CGRect(x: 0, y: 0, width: width, height: 2000)
            cell.layoutIfNeeded()
            let height = cell.contentView.systemLayoutSizeFitting(
                CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            ).height
            let container = UIView(frame: CGRect(x: 0, y: 0, width: width, height: height))
            container.backgroundColor = .systemBackground
            container.tintColor = lemmyTeal
            cell.frame = container.bounds
            container.addSubview(cell)
            container.layoutIfNeeded()
            assertSnapshot(
                matching: container,
                as: .image(
                    size: CGSize(width: width, height: height),
                    traits: UITraitCollection(traitsFrom: [
                        UITraitCollection(userInterfaceStyle: style),
                        UITraitCollection(displayScale: 2),
                    ])
                ),
                named: style == .dark ? "dark" : "light",
                testName: testName,
                line: line
            )
        }
    }
}
