//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

extension NSAttributedString.Key {
    /// Marks a mention/community handle range whose background is painted as a
    /// rounded pill by `ChipBackgroundLayoutManager`. The value is the fill color.
    static let mentionChipFill = NSAttributedString.Key("SpudMentionChipFill")
}

/// Paints a rounded pill behind every `.mentionChipFill` range. Drawing the chip as
/// a text background (rather than an attachment view) keeps the handle as real,
/// selectable text — so VoiceOver reads it, it wraps rather than truncating, and it
/// renders reliably both on device and in the offscreen snapshot pipeline (unlike a
/// TextKit-hosted attachment view, which neither populates).
final class ChipBackgroundLayoutManager: NSLayoutManager {
    /// Insets applied to each enclosing rect before rounding (negative grows the
    /// pill). The pill is padded by drawing, not by padding characters, so a wrapped
    /// chip never leaves an orphaned empty pill on the previous line.
    private let horizontalInset: CGFloat = -5
    private let verticalInset: CGFloat = 0.5
    private let cornerRadiusCap: CGFloat = 11

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let textStorage, let container = textContainers.first else { return }

        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        textStorage.enumerateAttribute(.mentionChipFill, in: charRange, options: []) { value, range, _ in
            guard let color = value as? UIColor else { return }
            color.setFill()
            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            enumerateEnclosingRects(
                forGlyphRange: glyphRange,
                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                in: container
            ) { rect, _ in
                let pill = rect.offsetBy(dx: origin.x, dy: origin.y)
                    .insetBy(dx: self.horizontalInset, dy: self.verticalInset)
                UIBezierPath(
                    roundedRect: pill,
                    cornerRadius: min(pill.height / 2, self.cornerRadiusCap)
                ).fill()
            }
        }
    }
}
