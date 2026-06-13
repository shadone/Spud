//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// The small bordered "ALT" badge marking an image as carrying a description.
/// Used in the media-viewer caption pill and the alt-text sheet header, the
/// universal accessibility marker for alternative text.
final class AltBadgeLabel: UILabel {
    private let insets = UIEdgeInsets(top: 0, left: 4, bottom: 1, right: 4)

    init(pointSize: CGFloat) {
        super.init(frame: .zero)
        text = "ALT"
        font = .systemFont(ofSize: pointSize, weight: .heavy)
        textColor = .white
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.55).cgColor
        layer.cornerRadius = 4
        layer.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        // The badge is decorative; the surrounding control carries the label.
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let base = super.intrinsicContentSize
        return CGSize(
            width: base.width + insets.left + insets.right,
            height: base.height + insets.top + insets.bottom
        )
    }
}
