//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudDataKit
import SpudUtilKit
import Testing
import UIKit
@testable import Spud

/// Regression guard for the community-feed overlap bug: the full feed error and
/// empty states used to render via the view-controller-level
/// `contentUnavailableConfiguration`, a transparent overlay across the WHOLE
/// view — including a scrolling header hosted as the table's `tableHeaderView`
/// (the community header) — so "Couldn't reach <host>" rendered see-through on
/// top of the header. The fix renders the same styled config into the table's
/// `backgroundView` (a `FeedStateSurfaceView`), below the header in z-order and
/// top-inset by the header height so it centers in the below-header region.
///
/// These tests drive the real `PostListViewController` through `applyLoadState`
/// and assert WHERE the surface lands: the VC-level config stays nil and the
/// backgroundView hosts the surface at the right inset. They also pin the
/// interplay with the loading skeleton, which shares the same `backgroundView`
/// slot.
@MainActor
struct PostListStateSurfaceTests {
    /// A known scrolling-header height, taller than half a typical table so the
    /// tall-header centering improvement is meaningful (the surface would hide
    /// under a bounds-centered layout).
    private let headerHeight: CGFloat = 420

    /// Builds a real `PostListViewController` on a frontpage feed backed by a
    /// signed-out account registered in the in-memory DB, so the failure path's
    /// `instanceHost` resolves cleanly (mirrors the sibling VC tests).
    private func makeViewController(
        dependencies: FakeDependencies = FakeDependencies()
    ) throws -> PostListViewController {
        let instance = try #require(InstanceActorId(from: "https://example.com"))
        let keychainId = dependencies.accountService.accountForSignedOut(
            forInstance: instance,
            isServiceAccount: false
        )
        let feed = FeedHandle(
            feedKey: "feed-1",
            feedType: .frontpage(listingType: .All, sortType: .Active)
        )
        let vc = PostListViewController(
            feed: feed,
            accountKeychainId: keychainId,
            dependencies: dependencies
        )
        vc.loadViewIfNeeded()
        return vc
    }

    /// A header with a deterministic measured height. The table re-measures its
    /// `tableHeaderView` via `systemLayoutSizeFitting`, so drive the height with
    /// an inner view pinned to all edges plus a fixed height constraint. The
    /// controller only re-measures once the table has a non-zero width; on an
    /// unlaid-out VC (`tableView.bounds.width == 0`) the assigned frame height is
    /// what `scrollingHeaderView?.frame.height` reports, so set it explicitly too.
    private func makeHeader(height: CGFloat) -> UIView {
        let header = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: height))
        let inner = UIView()
        inner.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: header.topAnchor),
            inner.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            inner.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            inner.heightAnchor.constraint(equalToConstant: height),
        ])
        return header
    }

    private func hostedContentUnavailableView(in surface: FeedStateSurfaceView) -> UIView? {
        surface.subviews.first { $0 is UIContentUnavailableView }
    }

    // MARK: - Test 1: failed state with a header renders below the header

    @Test
    func failedStateWithHeaderRendersInBackgroundViewBelowHeader() throws {
        let vc = try makeViewController()
        vc.setScrollingHeaderView(makeHeader(height: headerHeight))

        vc.applyLoadState(.failed(LoadFailure(kind: .unreachable, diagnostics: "test")))

        // The VC-level overlay is never used, so nothing renders on top of the header.
        #expect(vc.contentUnavailableConfiguration == nil)

        let surface = try #require(vc.tableView.backgroundView as? FeedStateSurfaceView)
        #expect(hostedContentUnavailableView(in: surface) != nil)
        #expect(surface.topInset == headerHeight)
    }

    // MARK: - Test 2: empty state with a header renders below the header

    @Test
    func emptyStateWithHeaderRendersInBackgroundViewBelowHeader() throws {
        let vc = try makeViewController()
        vc.setScrollingHeaderView(makeHeader(height: headerHeight))

        vc.applyLoadState(.empty)

        #expect(vc.contentUnavailableConfiguration == nil)

        let surface = try #require(vc.tableView.backgroundView as? FeedStateSurfaceView)
        #expect(hostedContentUnavailableView(in: surface) != nil)
        #expect(surface.topInset == headerHeight)
    }

    // MARK: - Test 3: transitions clear the surface; skeleton interplay is safe

    @Test
    func transitionToLoadedClearsSurfaceAndSkeletonInterplayIsSafe() throws {
        let vc = try makeViewController()
        vc.setScrollingHeaderView(makeHeader(height: headerHeight))

        // Loading (not pull-to-refresh) installs the skeleton in the shared slot.
        vc.applyLoadState(.loading(slow: false))
        #expect(vc.tableView.backgroundView is FeedLoadingSkeletonView)

        // The error surface replaces the skeleton in the same slot.
        vc.applyLoadState(.failed(LoadFailure(kind: .unreachable, diagnostics: "test")))
        #expect(vc.tableView.backgroundView is FeedStateSurfaceView)

        // Reloading returns to the skeleton without leaking the state surface.
        vc.applyLoadState(.loading(slow: false))
        #expect(vc.tableView.backgroundView is FeedLoadingSkeletonView)
        #expect(!(vc.tableView.backgroundView is FeedStateSurfaceView))

        // Settling to loaded clears the slot entirely.
        vc.applyLoadState(.loaded)
        #expect(vc.tableView.backgroundView == nil)
    }

    // MARK: - Test 4: no header (plain feed) installs the surface with inset 0

    @Test
    func plainFeedWithoutHeaderInstallsSurfaceWithZeroInset() throws {
        let vc = try makeViewController()
        // No scrolling header installed (plain Posts/Saved feed).

        vc.applyLoadState(.failed(LoadFailure(kind: .unreachable, diagnostics: "test")))

        #expect(vc.contentUnavailableConfiguration == nil)

        let surface = try #require(vc.tableView.backgroundView as? FeedStateSurfaceView)
        #expect(hostedContentUnavailableView(in: surface) != nil)
        #expect(surface.topInset == 0)
    }

    // MARK: - Test 5: loading state with a header installs the skeleton below it

    /// Mirrors the empty / failed cases for the loading skeleton, which shares the
    /// same `backgroundView` slot: with a scrolling header installed, the initial
    /// fetch's skeleton is inset below the header (not pinned behind it).
    @Test
    func loadingStateWithHeaderInstallsSkeletonBelowHeader() throws {
        let vc = try makeViewController()
        vc.setScrollingHeaderView(makeHeader(height: headerHeight))

        // Loading (not pull-to-refresh) installs the skeleton in the shared slot.
        vc.applyLoadState(.loading(slow: false))

        let skeleton = try #require(vc.tableView.backgroundView as? FeedLoadingSkeletonView)
        #expect(skeleton.topInset == headerHeight)
    }

    // MARK: - Test 6: header installed AFTER the skeleton re-insets it

    /// Regression guard for the blank below-header region while loading. The
    /// community cold-open order installs the skeleton (from the embedded feed's
    /// `viewDidLoad`) BEFORE the host installs its scrolling header, so installing
    /// the header must immediately re-inset the already-showing skeleton below it —
    /// otherwise the skeleton stays hidden behind the opaque header and the
    /// below-header area reads blank while posts fetch.
    @Test
    func loadingSkeletonReinsetsWhenHeaderInstalledAfterwards() throws {
        let vc = try makeViewController()

        // Skeleton shown first, with no header yet -> inset 0.
        vc.applyLoadState(.loading(slow: false))
        let skeleton = try #require(vc.tableView.backgroundView as? FeedLoadingSkeletonView)
        #expect(skeleton.topInset == 0)

        // Header installed afterwards -> the skeleton re-insets below it, even
        // though the table has no width yet (so the layout-measure path bails).
        vc.setScrollingHeaderView(makeHeader(height: headerHeight))
        #expect(vc.tableView.backgroundView is FeedLoadingSkeletonView)
        #expect(skeleton.topInset == headerHeight)
    }
}
