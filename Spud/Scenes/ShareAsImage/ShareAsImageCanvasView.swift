//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// The editor's dark "stage" behind the live preview: a fixed charcoal fill
/// with a faint dot grid, echoing the card's own `.square`/`.story` backdrop so
/// the preview reads as being composed on a surface. Fixed dark regardless of
/// the device appearance — a consistent editing stage makes both light and dark
/// cards pop, and matches the settled Editor C look. This is editor chrome, not
/// the card, so it does not use ``ShareCardPalette``.
final class ShareAsImageCanvasView: UIView {
    private static let dotSpacing: CGFloat = 22
    private static let dotRadius: CGFloat = 1

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.086, green: 0.090, blue: 0.102, alpha: 1)
        isOpaque = true
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setFillColor(UIColor(white: 1, alpha: 0.05).cgColor)
        var y = rect.minY + Self.dotSpacing / 2
        while y <= rect.maxY {
            var x = rect.minX + Self.dotSpacing / 2
            while x <= rect.maxX {
                context.fillEllipse(in: CGRect(
                    x: x - Self.dotRadius,
                    y: y - Self.dotRadius,
                    width: Self.dotRadius * 2,
                    height: Self.dotRadius * 2
                ))
                x += Self.dotSpacing
            }
            y += Self.dotSpacing
        }
    }
}
