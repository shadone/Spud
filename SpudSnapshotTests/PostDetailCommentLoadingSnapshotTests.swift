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

/// Snapshots of the post-detail comment loading states: the comment-shaped
/// skeleton placeholder, the "No comments yet" empty-state row, and the inline
/// "couldn't load comments" failed-state row (offline + unreachable), each in
/// light and dark. All are self-sizing in-flow rows (so they scroll below the post
/// header), rendered at their natural fitting height and a pinned display scale.
/// The skeleton's pulse is an infinite layer animation, so `stopAnimating()` is
/// called (and `startAnimating()` never is) to pin a static, full-opacity frame.
@MainActor
final class PostDetailCommentLoadingSnapshotTests: XCTestCase {
    private let width: CGFloat = 390

    private func traits(_ style: UIUserInterfaceStyle) -> UITraitCollection {
        UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: style),
            UITraitCollection(displayScale: 2),
            SnapshotDeterminism.contentSizeTrait,
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
        // The skeleton view is self-sizing now, so render it at its natural fitting
        // height rather than a fixed height (which would stretch the bottom-pinned
        // stack).
        let view = CommentLoadingSkeletonView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemBackground
        view.widthAnchor.constraint(equalToConstant: width).isActive = true
        let height = view.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        let size = CGSize(width: width, height: height)
        view.frame = CGRect(origin: .zero, size: size)
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
        // The empty state is a self-sizing in-flow cell now: render its content view
        // at its natural fitting height rather than a fixed height (which would let
        // the top-pinned stack float to the vertical center).
        let cell = PostDetailEmptyCommentsCell(style: .default, reuseIdentifier: nil)
        let content = cell.contentView
        content.translatesAutoresizingMaskIntoConstraints = false
        content.backgroundColor = .systemBackground
        content.widthAnchor.constraint(equalToConstant: width).isActive = true
        let height = content.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        let size = CGSize(width: width, height: height)
        content.frame = CGRect(origin: .zero, size: size)
        content.layoutIfNeeded()

        assertSnapshot(
            matching: content,
            as: .image(size: size, traits: traits(style)),
            named: style == .dark ? "dark" : "light",
            testName: testName,
            line: line
        )
    }

    func test_commentsFailedOffline_light() {
        assertFailed(kind: .offline, style: .light)
    }

    func test_commentsFailedOffline_dark() {
        assertFailed(kind: .offline, style: .dark)
    }

    func test_commentsFailedUnreachable_light() {
        assertFailed(kind: .unreachable, style: .light)
    }

    func test_commentsFailedUnreachable_dark() {
        assertFailed(kind: .unreachable, style: .dark)
    }

    private func assertFailed(
        kind: LoadFailure.Kind,
        style: UIUserInterfaceStyle,
        testName: String = #function,
        line: UInt = #line
    ) {
        // The failed state is a self-sizing in-flow cell with a Retry button.
        // Render its content view at its natural fitting height, like the empty
        // state above.
        let cell = PostDetailCommentsFailedCell(style: .default, reuseIdentifier: nil)
        cell.configure(with: LoadFailure(kind: kind, diagnostics: "snapshot"))
        let content = cell.contentView
        content.translatesAutoresizingMaskIntoConstraints = false
        content.backgroundColor = .systemBackground
        content.widthAnchor.constraint(equalToConstant: width).isActive = true
        let height = content.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        let size = CGSize(width: width, height: height)
        content.frame = CGRect(origin: .zero, size: size)
        content.layoutIfNeeded()

        assertSnapshot(
            matching: content,
            as: .image(size: size, traits: traits(style)),
            named: style == .dark ? "dark" : "light",
            testName: testName,
            line: line
        )
    }
}
