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

/// Snapshots of the optimistic DM bubble in its two pending states (sending and
/// failed), both light and dark. Mirrors `PostDetailPendingCommentSnapshotTests`
/// (the direct analog for the comment merge).
///
/// `DMBubbleCell` renders straight from its `configure(with:)` argument with no
/// image loading, so it is snapshot at a fixed width and pinned display scale —
/// the references are device-independent (any sim records/matches them), unlike
/// the full-screen app-level snapshots.
@MainActor
final class DMBubbleSnapshotTests: XCTestCase {
    private let lemmyTeal = UIColor(red: 0, green: 0x96 / 255, blue: 0x87 / 255, alpha: 1)
    private let width: CGFloat = 390

    // MARK: - Pending DM bubble states

    func test_dmBubble_sending() {
        let item = DMBubbleItem(
            id: -1_000_001,
            content: "On my way, see you in ten!",
            published: Date(timeIntervalSinceNow: -5),
            isOutgoing: true,
            pendingStatus: .sending,
            clientToken: "tok-sending"
        )
        assertBubble(item)
    }

    func test_dmBubble_failed() {
        let item = DMBubbleItem(
            id: -1_000_002,
            content: "On my way, see you in ten!",
            published: Date(timeIntervalSinceNow: -5),
            isOutgoing: true,
            pendingStatus: .failed,
            clientToken: "tok-failed"
        )
        assertBubble(item)
    }

    // MARK: - Helpers

    private func assertBubble(
        _ item: DMBubbleItem,
        testName: String = #function,
        line: UInt = #line
    ) {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let cell = renderCell(item: item)
            snapshot(cell, style: style, testName: testName, line: line)
        }
    }

    private func renderCell(item: DMBubbleItem) -> DMBubbleCell {
        let cell = DMBubbleCell(style: .default, reuseIdentifier: nil)
        cell.tintColor = lemmyTeal
        cell.contentView.tintColor = lemmyTeal
        cell.contentView.backgroundColor = .systemBackground
        cell.configure(with: item)
        return cell
    }

    private func snapshot(
        _ cell: DMBubbleCell,
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

        // Host the whole cell on an opaque backdrop so the tinted bubble + status
        // line stay legible in dark mode (the `.image` strategy reparents into a
        // fresh window otherwise transparent).
        let container = UIView(frame: CGRect(x: 0, y: 0, width: width, height: height))
        container.backgroundColor = .systemBackground
        container.tintColor = lemmyTeal
        cell.frame = container.bounds
        container.addSubview(cell)
        container.layoutIfNeeded()

        assertSnapshot(
            matching: container,
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
