//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
import UIKit
@testable import Spud

@MainActor
struct ListZoomSourceTests {
    private enum Section: Hashable { case main }

    private func makeTable(items: [Int]) -> (UITableView, UITableViewDiffableDataSource<Section, Int>) {
        let table = UITableView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        table.register(UITableViewCell.self, forCellReuseIdentifier: "c")
        let ds = UITableViewDiffableDataSource<Section, Int>(tableView: table) { tv, ip, _ in
            tv.dequeueReusableCell(withIdentifier: "c", for: ip)
        }
        var snap = NSDiffableDataSourceSnapshot<Section, Int>()
        snap.appendSections([.main])
        snap.appendItems(items)
        ds.apply(snap, animatingDifferences: false)
        table.layoutIfNeeded()
        return (table, ds)
    }

    @Test
    func returnsNilForItemAbsentFromSnapshot() {
        let (table, ds) = makeTable(items: [1, 2, 3])
        let result = listZoomSource(tableView: table, dataSource: ds, item: 999) { $0.contentView }
        #expect(result == nil)
    }

    @Test
    func resolvesContentViewForPresentItem() {
        let (table, ds) = makeTable(items: [1, 2, 3])
        let result = listZoomSource(tableView: table, dataSource: ds, item: 1) { $0.contentView }
        #expect(result != nil)
    }

    @Test
    func scrollsAnOffscreenItemOnScreenThenResolves() {
        // 200 rows in a 480pt table: item 190 starts far below the fold.
        let (table, ds) = makeTable(items: Array(0..<200))
        let before = table.indexPathsForVisibleRows ?? []
        #expect(!before.contains(IndexPath(row: 190, section: 0)))
        let result = listZoomSource(tableView: table, dataSource: ds, item: 190) { $0.contentView }
        #expect(result != nil)
        #expect(table.indexPathsForVisibleRows?.contains(IndexPath(row: 190, section: 0)) == true)
    }

    @Test
    func returnsNilWhenTheResolvedIndexPathIsOutOfBoundsForTheTable() {
        // Simulates a live snapshot apply racing this provider (the feed can
        // keep applying snapshots while the viewer is open): the data source
        // resolves a valid index path, but the table it's paired with here
        // has no rows for it — `scrollToRow(at:)` would otherwise raise.
        let (_, ds) = makeTable(items: [1, 2, 3])
        let staleTable = UITableView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let result = listZoomSource(tableView: staleTable, dataSource: ds, item: 1) { $0.contentView }
        #expect(result == nil)
    }
}
