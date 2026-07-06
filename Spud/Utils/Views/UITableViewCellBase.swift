//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import UIKit

/// Base class for cells with some common helpers.
class UITableViewCellBase: UITableViewCell {
    /// Reference to the parent table that containing this cell.
    weak var tableView: UITableView?

    /// Returns true when we are inside `func tableView(_:, cellForRowAt:)`
    ///
    /// While being configured layout changes are picked up automatically; otherwise
    /// we need to explicitly tell the UITableView that the row height has changed, via
    /// `tableView.remeasureRowHeightsWithoutAnimation()`. Re-measuring with a plain
    /// animated `beginUpdates()/endUpdates()` (or `performBatchUpdates(nil)`) interpolates
    /// any newly installed, never-laid-out subview's frame from `.zero` to its final
    /// frame — visible as content zooming in from a corner (e.g. a late-loading inline
    /// body image).
    var isBeingConfigured: Bool = false

    override func prepareForReuse() {
        super.prepareForReuse()
        tableView = nil
    }
}
