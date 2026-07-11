//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudUtilKit
import UIKit

/// A `UILabel` with small horizontal padding, used for the rounded badge pills
/// (author-status pills, the comment score pill, and the collapsed "N new" pill).
final class BadgeLabel: UILabel {
    private let insets = UIEdgeInsets(top: 1, left: 5, bottom: 1, right: 5)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(
            width: size.width + insets.left + insets.right,
            height: size.height + insets.top + insets.bottom
        )
    }
}

/// Builds one rounded pill for an author badge, tinting an accent-following
/// badge (OP) with the resolved `accent` and every other badge with its own
/// `color`. A solid badge fills with the color and draws white text; a tinted
/// badge fills with a 16%-alpha wash and draws the color as text.
@MainActor
func makeAuthorBadgeView(_ badge: AuthorBadge, accent: UIColor) -> UIView {
    let label = BadgeLabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.layer.cornerRadius = 4
    label.clipsToBounds = true
    label.setContentHuggingPriority(.required, for: .horizontal)
    label.setContentCompressionResistancePriority(.required, for: .horizontal)

    let color = badge.usesAccent ? accent : badge.color
    let textColor: UIColor = badge.solid ? .white : color
    label.backgroundColor = badge.solid ? color : color.withAlphaComponent(0.16)

    let attributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 11, weight: .bold),
        .foregroundColor: textColor,
    ]
    let text = NSMutableAttributedString()
    if let symbolName = badge.symbolName, let image = UIImage(systemName: symbolName) {
        text.append(NSAttributedString.symbol(from: image, attributes: attributes))
        text.append(NSAttributedString(string: " ", attributes: attributes))
    }
    text.append(NSAttributedString(string: badge.text, attributes: attributes))
    label.attributedText = text
    return label
}
