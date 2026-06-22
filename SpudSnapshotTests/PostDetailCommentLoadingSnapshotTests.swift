//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import UIKit
import XCTest
@testable import Spud

/// Snapshots of the post-detail comment loading states: the comment-shaped
/// skeleton placeholder and the "No comments yet" empty view, each in light and
/// dark. Both render at a fixed size and pinned display scale, so the references
/// are device-independent. The skeleton's pulse is an infinite layer animation,
/// so `stopAnimating()` is called (and `startAnimating()` never is) to pin a
/// static, full-opacity frame.
@MainActor
final class PostDetailCommentLoadingSnapshotTests: XCTestCase {
    private let width: CGFloat = 390

    private func traits(_ style: UIUserInterfaceStyle) -> UITraitCollection {
        UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: style),
            UITraitCollection(displayScale: 2),
        ])
    }

    func test_commentSkeleton_light() {
        assertSkeleton(style: .light)
    }

    func test_commentSkeleton_dark() {
        assertSkeleton(style: .dark)
    }

    private func assertSkeleton(
        style: UIUserInterfaceStyle,
        testName: String = #function,
        line: UInt = #line
    ) {
        let size = CGSize(width: width, height: 500)
        let view = CommentLoadingSkeletonView(frame: CGRect(origin: .zero, size: size))
        view.backgroundColor = .systemBackground
        view.stopAnimating()
        view.layoutIfNeeded()

        assertSnapshot(
            matching: view,
            as: .image(size: size, traits: traits(style)),
            named: style == .dark ? "dark" : "light",
            testName: testName,
            line: line
        )
    }

    func test_emptyComments_light() {
        assertEmpty(style: .light)
    }

    func test_emptyComments_dark() {
        assertEmpty(style: .dark)
    }

    private func assertEmpty(
        style: UIUserInterfaceStyle,
        testName: String = #function,
        line: UInt = #line
    ) {
        let size = CGSize(width: width, height: 320)
        let view = PostDetailEmptyCommentsView(frame: CGRect(origin: .zero, size: size))
        view.backgroundColor = .systemBackground
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
