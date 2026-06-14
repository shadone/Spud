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

/// Snapshots of the post-detail comment cell across its content and moderation
/// states: a normal comment, the original-poster ("OP") tag, a collapsed
/// comment with a descendant count, deleted, removed, distinguished (mod),
/// an upvoted comment, and a deeply nested comment whose depth makes the
/// `DepthRailsView` draw a stack of rails — each in light and dark.
///
/// The cell is rendered straight from a `PostDetailCommentRow` fixture and a
/// real `AppearanceService`, with no database or network: the view model is a
/// pure transform of the row. The cell is a plain `UITableViewCell` that does
/// not read a table width, so it self-sizes via `contentView`'s fitting size at
/// a fixed width and pinned display scale, making the references
/// device-independent.
@MainActor
final class PostDetailCommentSnapshotTests: XCTestCase {
    private let lemmyTeal = UIColor(red: 0, green: 0x96 / 255, blue: 0x87 / 255, alpha: 1)
    private let width: CGFloat = 390

    // MARK: - Comment cell states

    func test_normal() {
        assertComment(viewModel: makeViewModel(row: row()))
    }

    func test_originalPoster() {
        // Matching creator/post person ids drives the "OP" tag.
        assertComment(viewModel: makeViewModel(
            row: row(creatorPersonId: 42),
            postCreatorPersonId: 42
        ))
    }

    func test_collapsed_withDescendantCount() {
        assertComment(viewModel: makeViewModel(
            row: row(),
            isCollapsed: true,
            collapsedDescendantCount: 7
        ))
    }

    func test_deleted() {
        assertComment(viewModel: makeViewModel(
            row: row(body: "[deleted]", isDeleted: true)
        ))
    }

    func test_removed() {
        assertComment(viewModel: makeViewModel(
            row: row(body: "[removed by moderator]", isRemoved: true)
        ))
    }

    func test_distinguished() {
        assertComment(viewModel: makeViewModel(
            row: row(body: "Reminder: keep it civil. — Mod team", isDistinguished: true)
        ))
    }

    func test_upvoted() {
        assertComment(viewModel: makeViewModel(
            row: row(score: 256, voteStatus: 1)
        ))
    }

    func test_deeplyNested() {
        // depth 4 => 3 ancestor rails, so DepthRailsView draws a stack.
        assertComment(viewModel: makeViewModel(
            row: row(depth: 4)
        ))
    }

    // MARK: - Comment cell rendering

    private func assertComment(
        viewModel: PostDetailCommentViewModel,
        testName: String = #function,
        line: UInt = #line
    ) {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let cell = renderCell(viewModel: viewModel)
            snapshot(cell, style: style, testName: testName, line: line)
        }
    }

    private func renderCell(viewModel: PostDetailCommentViewModel) -> PostDetailCommentCell {
        let cell = PostDetailCommentCell(style: .default, reuseIdentifier: nil)
        // Pin the accent on the snapshot root: the `.image` strategy reparents
        // `contentView` into a fresh window, so without its own tintColor the
        // "OP" pill would inherit the window's system blue instead of the brand
        // teal that the cell follows at runtime.
        cell.tintColor = lemmyTeal
        cell.contentView.tintColor = lemmyTeal
        // The cell is transparent and sits on the table's background at runtime;
        // give the snapshot the same opaque backdrop so `label`-colored text
        // stays legible (white-on-transparent would vanish in dark mode).
        cell.contentView.backgroundColor = .systemBackground

        cell.configure(with: viewModel)
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

    private func makeViewModel(
        row: PostDetailCommentRow,
        postCreatorPersonId: Int64? = nil,
        isCollapsed: Bool = false,
        collapsedDescendantCount: Int? = nil
    ) -> PostDetailCommentViewModel {
        let appearance = AppearanceService(preferencesService: PreferencesService())
        return PostDetailCommentViewModel(
            row: row,
            appearance: appearance,
            postCreatorPersonId: postCreatorPersonId,
            isCollapsed: isCollapsed,
            collapsedDescendantCount: collapsedDescendantCount
        )
    }

    // MARK: - DepthRailsView component states

    func test_depthRails_zero() {
        assertRails([], width: 1)
    }

    func test_depthRails_one() {
        assertRails([.systemRed])
    }

    func test_depthRails_three() {
        assertRails([.systemRed, .systemGreen, .systemBlue])
    }

    func test_depthRails_five() {
        assertRails([.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue])
    }

    private func assertRails(
        _ colors: [UIColor],
        width: CGFloat? = nil,
        testName: String = #function,
        line: UInt = #line
    ) {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let view = DepthRailsView()
            view.railColors = colors
            // Honor the view's intrinsic width (zero for no rails); fall back to
            // a fixed value only when the caller forces a non-zero canvas.
            let renderWidth = width ?? max(view.intrinsicContentSize.width, 1)
            assertSnapshot(
                matching: view,
                as: .image(
                    size: CGSize(width: renderWidth, height: 60),
                    traits: traits(style)
                ),
                named: style == .dark ? "dark" : "light",
                testName: testName,
                line: line
            )
        }
    }

    // MARK: - Helpers

    private func traits(_ style: UIUserInterfaceStyle) -> UITraitCollection {
        UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: style),
            UITraitCollection(displayScale: 2),
        ])
    }

    // MARK: - Fixtures

    private func row(
        depth: Int64 = 1,
        body: String? = "Beautiful shot — the reflection on the water is what sells it.",
        score: Int64 = 128,
        voteStatus: Int64? = nil,
        isSaved: Bool? = false,
        isRemoved: Bool? = false,
        isDistinguished: Bool? = false,
        isDeleted: Bool? = false,
        creatorPersonId: Int64? = 1
    ) -> PostDetailCommentRow {
        PostDetailCommentRow(
            id: 1,
            position: 1,
            depth: depth,
            serverCommentId: 1,
            body: body,
            originalCommentUrl: "https://lemmy.world/comment/1",
            score: score,
            voteStatus: voteStatus,
            isSaved: isSaved,
            isRemoved: isRemoved,
            isDistinguished: isDistinguished,
            isDeleted: isDeleted,
            published: Date(timeIntervalSinceNow: -3 * 3600),
            creatorName: "ansel",
            creatorPersonId: creatorPersonId,
            creatorInstanceActorId: "https://lemmy.world",
            moreChildCount: nil,
            moreParentId: nil
        )
    }
}
