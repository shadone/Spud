//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SpudDataKit
import Testing
import UIKit
@testable import Spud

/// The feed switcher's "Downloaded" row is gated on there being downloaded posts
/// to read: it appears only when `downloadedCount() > 0`, and is re-evaluated on
/// every appearance so a fresh download surfaces it (and clearing the downloads
/// removes it) without rebuilding the controller.
@MainActor
struct FeedSwitcherViewControllerTests {
    private func makeSwitcher(downloadedCount: @escaping @MainActor () -> Int) -> FeedSwitcherViewController {
        FeedSwitcherViewController(
            currentFeedType: { nil },
            defaultSortType: { .Active },
            downloadedCount: downloadedCount
        )
    }

    /// The four always-present feeds: All / Local / Subscribed / Saved.
    private let baseFeedRowCount = 4

    @Test
    func downloadedRowHiddenWhenCountIsZero() {
        let vc = makeSwitcher(downloadedCount: { 0 })
        vc.loadViewIfNeeded()
        vc.viewWillAppear(false)

        let table = UITableView()
        #expect(vc.tableView(table, numberOfRowsInSection: 0) == baseFeedRowCount)
    }

    @Test
    func downloadedRowShownWhenCountIsPositive() {
        let vc = makeSwitcher(downloadedCount: { 3 })
        vc.loadViewIfNeeded()
        vc.viewWillAppear(false)

        let table = UITableView()
        #expect(vc.tableView(table, numberOfRowsInSection: 0) == baseFeedRowCount + 1)
    }

    /// Regression test for the Liquid Glass popover fix (Task 22): a row cell
    /// must be transparent in the popover presentation so the popover's own
    /// glass material shows through, rather than painting its own opaque
    /// `.secondarySystemGroupedBackground` pill on top of it. `isPopover`
    /// reads `modalPresentationStyle`, which the real caller sets right after
    /// construction and before the view loads -- mirrored here by setting it
    /// before `loadViewIfNeeded()`.
    @Test
    func popoverRowBackgroundIsClearForGlass() {
        let vc = makeSwitcher(downloadedCount: { 0 })
        vc.modalPresentationStyle = .popover
        vc.loadViewIfNeeded()

        let table = UITableView()
        table.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        let cell = vc.tableView(table, cellForRowAt: IndexPath(row: 0, section: 0))

        #expect(cell.backgroundColor == .clear)
    }

    /// Companion to the above: the pushed (compact-width, beneath-the-list)
    /// usage never touches `modalPresentationStyle`, so it must keep its
    /// opaque grouped-list appearance. A fix that clears the popover's row
    /// backgrounds but ALSO clears the pushed screen's would be a regression
    /// this test alone would catch -- it is not enough to assert `.clear` in
    /// the popover case above.
    @Test
    func pushedRowBackgroundStaysOpaque() {
        let vc = makeSwitcher(downloadedCount: { 0 })
        // modalPresentationStyle left at its default (never `.popover`).
        vc.loadViewIfNeeded()

        let table = UITableView()
        table.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        let cell = vc.tableView(table, cellForRowAt: IndexPath(row: 0, section: 0))

        #expect(cell.backgroundColor == .secondarySystemGroupedBackground)
    }

    @Test
    func downloadedRowAppearsAndDisappearsAcrossReappearances() {
        var count = 0
        let vc = makeSwitcher(downloadedCount: { count })
        vc.loadViewIfNeeded()
        let table = UITableView()

        vc.viewWillAppear(false)
        #expect(vc.tableView(table, numberOfRowsInSection: 0) == baseFeedRowCount)

        // A download lands; on next appearance the row shows.
        count = 5
        vc.viewWillAppear(false)
        #expect(vc.tableView(table, numberOfRowsInSection: 0) == baseFeedRowCount + 1)

        // Downloads cleared; on next appearance the row is gone again.
        count = 0
        vc.viewWillAppear(false)
        #expect(vc.tableView(table, numberOfRowsInSection: 0) == baseFeedRowCount)
    }
}
