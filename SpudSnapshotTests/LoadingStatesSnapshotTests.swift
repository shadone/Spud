//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import UIKit
import XCTest
@testable import Spud

/// Snapshots of the feed's loading affordances: the table-footer "loading more"
/// cell (a centered activity indicator) and the initial-fetch skeleton
/// placeholder (a column of pulsing thumbnail + text-bar rows), each in light
/// and dark.
///
/// Both render at a fixed size and pinned display scale, so the references are
/// device-independent. The skeleton's pulse is an infinite layer animation, so
/// `stopAnimating()` is called (and `startAnimating()` never is) to pin a static
/// frame — the references capture the at-rest, full-opacity bars rather than a
/// non-deterministic point in the fade.
@MainActor
final class LoadingStatesSnapshotTests: XCTestCase {
    private let lemmyTeal = UIColor(red: 0, green: 0x96 / 255, blue: 0x87 / 255, alpha: 1)
    private let width: CGFloat = 390

    private func traits(_ style: UIUserInterfaceStyle) -> UITraitCollection {
        UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: style),
            UITraitCollection(displayScale: 2),
        ])
    }

    // MARK: - LoadingFooterCell

    func test_loadingFooter_light() {
        assertLoadingFooter(style: .light)
    }

    func test_loadingFooter_dark() {
        assertLoadingFooter(style: .dark)
    }

    private func assertLoadingFooter(
        style: UIUserInterfaceStyle,
        testName: String = #function,
        line: UInt = #line
    ) {
        let cell = LoadingFooterCell(style: .default, reuseIdentifier: nil)
        // Pin the accent on the snapshot root: the `.image` strategy reparents
        // `contentView` into a fresh window, so without its own tintColor the
        // indicator would inherit the window's system blue instead of the brand
        // teal the spinner follows at runtime.
        cell.tintColor = lemmyTeal
        cell.contentView.tintColor = lemmyTeal
        // The cell is transparent over the table background at runtime; give the
        // snapshot the same opaque backdrop so the indicator stays legible.
        cell.contentView.backgroundColor = .systemBackground

        cell.frame = CGRect(x: 0, y: 0, width: width, height: 200)
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

    // MARK: - FeedLoadingSkeletonView

    func test_skeleton_light() {
        assertSkeleton(style: .light)
    }

    func test_skeleton_dark() {
        assertSkeleton(style: .dark)
    }

    private func assertSkeleton(
        style: UIUserInterfaceStyle,
        testName: String = #function,
        line: UInt = #line
    ) {
        let size = CGSize(width: width, height: 600)
        let view = FeedLoadingSkeletonView(frame: CGRect(origin: .zero, size: size))
        view.backgroundColor = .systemBackground
        // Pin a static frame: the pulse is an infinite, non-deterministic layer
        // animation, so never start it (and stop it defensively).
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
}
