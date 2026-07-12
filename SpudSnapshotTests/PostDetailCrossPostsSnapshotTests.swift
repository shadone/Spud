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

/// Snapshot of the post-detail "Cross-posted to N communities" cell, rendered
/// straight from `CrossPostSummary` fixtures with no database or network — the
/// cell is a pure transform of the summaries it's configured with. Covers two
/// rows (so the inter-row divider renders) with one plural and one singular
/// score/comment count, in light and dark.
///
/// Matches `PostDetailCommentSnapshotTests`'s device-independent rendering:
/// the cell self-sizes via `contentView`'s fitting size at a fixed width and
/// pinned display scale, so the references don't depend on the host device.
@MainActor
final class PostDetailCrossPostsSnapshotTests: XCTestCase {
    private let width: CGFloat = 390

    func test_twoCrossPosts() {
        // Two rows: one with plural score/comment counts, one with singular
        // ("1 point · 1 comment") to cover the pluralization fix in the same
        // render.
        assertCell(crossPosts: [
            crossPost(
                serverPostId: 1,
                communityName: "pics",
                communityActorId: "https://lemmy.world/c/pics",
                score: 128,
                commentCount: 42
            ),
            crossPost(
                serverPostId: 2,
                communityName: "photography",
                communityActorId: "https://lemmy.zip/c/photography",
                score: 1,
                commentCount: 1
            ),
        ])
    }

    // MARK: - Rendering

    private func assertCell(
        crossPosts: [CrossPostSummary],
        testName: String = #function,
        line: UInt = #line
    ) {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let cell = renderCell(crossPosts: crossPosts)
            snapshot(cell, style: style, testName: testName, line: line)
        }
    }

    private func renderCell(crossPosts: [CrossPostSummary]) -> PostDetailCrossPostsCell {
        let cell = PostDetailCrossPostsCell(style: .default, reuseIdentifier: nil)
        // The cell is transparent and sits on the table's background at
        // runtime; give the snapshot the same opaque backdrop so `label`-
        // colored text stays legible (white-on-transparent would vanish in
        // dark mode). Matches `PostDetailCommentSnapshotTests.renderCell`.
        cell.contentView.backgroundColor = .systemBackground
        cell.configure(with: crossPosts)
        return cell
    }

    private func snapshot(
        _ cell: PostDetailCrossPostsCell,
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
            SnapshotDeterminism.contentSizeTrait,
        ])
    }

    // MARK: - Fixtures

    private func crossPost(
        serverPostId: Int64,
        communityName: String,
        communityActorId: String?,
        score: Int64,
        commentCount: Int64
    ) -> CrossPostSummary {
        CrossPostSummary(
            serverPostId: serverPostId,
            apId: "https://lemmy.world/post/\(serverPostId)",
            communityName: communityName,
            communityActorId: communityActorId,
            score: score,
            commentCount: commentCount
        )
    }
}
