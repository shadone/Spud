//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Resolves the live zoom-source view for a diffable list item, scrolling the
/// item on screen first when it is currently off screen.
///
/// Used by the media viewer's `zoomSource` closures on list-backed surfaces
/// (feed, Person "Posts", Activity): on dismiss the zoom transition asks for the
/// source view, and if the user scrolled the originating cell out of sight we
/// bring it back — non-animated, so the reveal does not compound with the zoom —
/// then hand back its thumbnail. Returns nil when `item` is no longer in the
/// snapshot (e.g. the feed refreshed the post away) or when its cell still
/// can't be resolved after scrolling it into view, either of which degrades
/// the transition to a plain fade.
@MainActor
func listZoomSource<Item: Hashable>(
    tableView: UITableView,
    dataSource: UITableViewDiffableDataSource<some Hashable, Item>,
    item: Item,
    thumbnail: (UITableViewCell) -> UIView?
) -> UIView? {
    guard let indexPath = dataSource.indexPath(for: item) else { return nil }
    // A live snapshot apply can land between the data source resolving this
    // index path and the scroll below (this provider is invoked mid-drag
    // while the feed keeps applying snapshots), so re-validate the index path
    // against the table's current section/row counts before scrolling to it —
    // `scrollToRow(at:)` otherwise raises for a now-out-of-range path.
    guard
        indexPath.section < tableView.numberOfSections,
        indexPath.row < tableView.numberOfRows(inSection: indexPath.section)
    else { return nil }
    if tableView.cellForRow(at: indexPath) == nil {
        // Off screen: bring it on, synchronously, before the morph commits.
        tableView.scrollToRow(at: indexPath, at: .none, animated: false)
        tableView.layoutIfNeeded()
    }
    guard let cell = tableView.cellForRow(at: indexPath) else { return nil }
    return thumbnail(cell)
}
