//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

extension UITableView {
    /// Re-measures self-sizing rows in place WITHOUT the implicit
    /// batch-updates animation. Use this whenever async content (an inline
    /// body image, a late thumbnail) changes a row's height after display:
    /// the newly installed subviews have never been laid out, so an animated
    /// re-measure interpolates their frames from .zero — reading as the
    /// content zooming in from a corner (the post-header cell documented
    /// this exact symptom; see PostDetailHeaderCell.adjustHeightForChange).
    func remeasureRowHeightsWithoutAnimation() {
        UIView.performWithoutAnimation {
            performBatchUpdates(nil)
        }
    }
}
