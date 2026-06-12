//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Draws a set of thin vertical colored rails — one per comment-thread
/// ancestor depth — on the leading edge of a comment cell. Each rail is laid
/// out left to right, oldest ancestor first, so a deeply nested comment shows a
/// scannable stack of hues. Top-level comments (no ancestors) draw nothing and
/// collapse to zero width.
final class DepthRailsView: UIView {
    /// One color per ancestor rail, leading edge first. Setting this resizes
    /// the view and redraws.
    var railColors: [UIColor] = [] {
        didSet {
            guard railColors != oldValue else { return }
            invalidateIntrinsicContentSize()
            setNeedsDisplay()
        }
    }

    /// Width of a single rail line.
    private let railWidth: CGFloat = 2
    /// Gap between adjacent rails.
    private let railSpacing: CGFloat = 6
    /// Alpha applied to each rail so it stays subtle in light and dark.
    private let railAlpha: CGFloat = 0.55

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        // The rails are decorative; the cell's tap gesture should pass through.
        isUserInteractionEnabled = false

        // Redraw when the light/dark appearance changes so display-P3 colors
        // re-resolve. Uses the iOS 17+ trait-change registration API.
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
            self.setNeedsDisplay()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        guard !railColors.isEmpty else {
            return CGSize(width: 0, height: UIView.noIntrinsicMetric)
        }
        let count = CGFloat(railColors.count)
        let width = count * railWidth + (count - 1) * railSpacing
        return CGSize(width: width, height: UIView.noIntrinsicMetric)
    }

    override func draw(_ rect: CGRect) {
        var x: CGFloat = 0
        for color in railColors {
            let railRect = CGRect(x: x, y: 0, width: railWidth, height: bounds.height)
            let path = UIBezierPath(roundedRect: railRect, cornerRadius: railWidth / 2)
            color.withAlphaComponent(railAlpha).setFill()
            path.fill()
            x += railWidth + railSpacing
        }
    }
}
