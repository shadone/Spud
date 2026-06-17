//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// A simple flow-layout container that wraps its items onto multiple rows.
/// Used for the health pills and the tag chips.
final class InstanceWrapView: UIView {
    var hSpacing: CGFloat = 7
    var vSpacing: CGFloat = 7

    private var items: [UIView] = []
    private var lastWidth: CGFloat = 0

    func setItems(_ views: [UIView]) {
        items.forEach { $0.removeFromSuperview() }
        items = views
        views.forEach { addSubview($0) }
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width != lastWidth {
            lastWidth = bounds.width
            invalidateIntrinsicContentSize()
        }
        layout(width: bounds.width, apply: true)
    }

    override var intrinsicContentSize: CGSize {
        let width = bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width
        return CGSize(width: UIView.noIntrinsicMetric, height: layout(width: width, apply: false))
    }

    @discardableResult
    private func layout(width: CGFloat, apply: Bool) -> CGFloat {
        guard width > 0 else { return 0 }
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in items {
            let size = view.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + vSpacing
                rowHeight = 0
            }
            if apply {
                view.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
            }
            x += size.width + hSpacing
            rowHeight = max(rowHeight, size.height)
        }
        return y + rowHeight
    }
}
