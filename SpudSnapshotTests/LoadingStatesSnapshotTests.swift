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

    // MARK: - PaginationErrorFooterCell

    func test_paginationErrorFooter_light() {
        assertPaginationErrorFooter(style: .light)
    }

    func test_paginationErrorFooter_dark() {
        assertPaginationErrorFooter(style: .dark)
    }

    private func assertPaginationErrorFooter(
        style: UIUserInterfaceStyle,
        testName: String = #function,
        line: UInt = #line
    ) {
        let cell = PaginationErrorFooterCell(style: .default, reuseIdentifier: nil)
        cell.tintColor = lemmyTeal
        cell.contentView.tintColor = lemmyTeal
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

    // MARK: - FeedLoadingSkeletonView (slow-hint)

    func test_skeletonSlow_light() {
        assertSkeletonSlow(style: .light)
    }

    func test_skeletonSlow_dark() {
        assertSkeletonSlow(style: .dark)
    }

    private func assertSkeletonSlow(
        style: UIUserInterfaceStyle,
        testName: String = #function,
        line: UInt = #line
    ) {
        let size = CGSize(width: width, height: 600)
        let view = FeedLoadingSkeletonView(frame: CGRect(origin: .zero, size: size))
        view.backgroundColor = .systemBackground
        // Show the slow-connection hint label before pinning the static frame.
        view.setShowsSlowHint(true)
        // Pin a static frame: the pulse is an infinite, non-deterministic layer
        // animation, so never start it (and stop it defensively).
        view.stopAnimating()
        // stopAnimating() hides the slow label; re-show it after stopping.
        view.setShowsSlowHint(true)
        view.layoutIfNeeded()

        assertSnapshot(
            matching: view,
            as: .image(size: size, traits: traits(style)),
            named: style == .dark ? "dark" : "light",
            testName: testName,
            line: line
        )
    }

    // MARK: - Error states

    func test_errorOffline_light() {
        assertErrorState(.offline, host: "lemmy.world", style: .light)
    }

    func test_errorOffline_dark() {
        assertErrorState(.offline, host: "lemmy.world", style: .dark)
    }

    func test_errorUnreachable_light() {
        assertErrorState(.unreachable, host: "lemmy.world", style: .light)
    }

    func test_errorUnreachable_dark() {
        assertErrorState(.unreachable, host: "lemmy.world", style: .dark)
    }

    func test_errorMalformed_light() {
        assertErrorState(.malformedResponse, host: "lemmy.world", style: .light)
    }

    func test_errorMalformed_dark() {
        assertErrorState(.malformedResponse, host: "lemmy.world", style: .dark)
    }

    /// Builds a `UIContentUnavailableView` from the real `FeedStatePresenter.descriptor`
    /// so the snapshot captures the actual icon + copy + buttons.
    ///
    /// Note: this deliberately mirrors the descriptor-to-config mapping in the
    /// view controller (minus the non-rendered action closures). If the controller's
    /// mapping diverges from the presenter's descriptor, this test will still pass
    /// because it re-runs the same descriptor→config logic rather than referencing
    /// the controller directly.
    private func assertErrorState(
        _ kind: LoadFailure.Kind,
        host: String?,
        style: UIUserInterfaceStyle,
        testName: String = #function,
        line: UInt = #line
    ) {
        let descriptor = FeedStatePresenter.descriptor(for: kind, host: host)
        var config = UIContentUnavailableConfiguration.empty()
        config.image = UIImage(systemName: descriptor.symbolName)
        config.text = descriptor.title
        config.secondaryText = descriptor.message
        var primary = UIButton.Configuration.borderedProminent()
        primary.title = descriptor.primary.title
        primary.baseBackgroundColor = lemmyTeal
        config.button = primary
        if let secondary = descriptor.secondary {
            var s = UIButton.Configuration.plain()
            s.title = secondary.title
            config.secondaryButton = s
        }
        let view = UIContentUnavailableView(configuration: config)
        view.backgroundColor = .systemBackground
        let size = CGSize(width: width, height: 400)
        view.frame = CGRect(origin: .zero, size: size)
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
