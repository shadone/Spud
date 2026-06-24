//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import SpudDataKit
import SpudUIKit
import UIKit
import XCTest
@testable import Spud

/// Snapshots of the pending-comment cell in its two states (sending and failed),
/// both light and dark, at depth 1 (one ancestor rail). The cell is configured
/// via `PostDetailCommentCell.configurePending(_:imageService:)` with a
/// `StaticImageService` so no async image loading is involved.
@MainActor
final class PostDetailPendingCommentSnapshotTests: XCTestCase {
    private let lemmyTeal = UIColor(red: 0, green: 0x96 / 255, blue: 0x87 / 255, alpha: 1)
    private let width: CGFloat = 390

    // MARK: - Pending comment states

    func test_pendingComment_sending() {
        assertPending(state: .init(
            clientToken: "tok-sending",
            body: "This is my reply, sending now.",
            depth: 1,
            status: .sending
        ))
    }

    func test_pendingComment_failed() {
        assertPending(state: .init(
            clientToken: "tok-failed",
            body: "This is my reply, sending now.",
            depth: 1,
            status: .failed
        ))
    }

    // MARK: - Helpers

    private func assertPending(
        state: PendingCommentCellState,
        testName: String = #function,
        line: UInt = #line
    ) {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let cell = renderCell(state: state)
            snapshot(cell, style: style, testName: testName, line: line)
        }
    }

    private func renderCell(state: PendingCommentCellState) -> PostDetailCommentCell {
        let cell = PostDetailCommentCell(style: .default, reuseIdentifier: nil)
        cell.tintColor = lemmyTeal
        cell.contentView.tintColor = lemmyTeal
        cell.contentView.backgroundColor = .systemBackground
        cell.configurePending(state, imageService: StaticImageService())
        return cell
    }

    private func snapshot(
        _ cell: PostDetailCommentCell,
        style: UIUserInterfaceStyle,
        testName: String,
        line: UInt
    ) {
        cell.frame = CGRect(x: 0, y: 0, width: width, height: 2000)
        cell.layoutIfNeeded()
        let height = cell.contentView.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height

        assertSnapshot(
            matching: cell.contentView,
            as: .image(size: CGSize(width: width, height: height), traits: traits(style)),
            named: style == .dark ? "dark" : "light",
            testName: testName,
            line: line
        )
    }

    private func traits(_ style: UIUserInterfaceStyle) -> UITraitCollection {
        UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: style),
            UITraitCollection(displayScale: 2),
        ])
    }
}
