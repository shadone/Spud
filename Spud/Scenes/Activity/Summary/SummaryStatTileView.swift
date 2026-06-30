//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SpudUIKit
import UIKit

/// A single stat tile: SF Symbol icon (top), large tabular value (middle),
/// category label (bottom), and an optional "new" badge.
///
/// Forward-source tiles render the icon with the view's `tintColor`; all
/// others use `.secondaryLabel`.
@MainActor
final class SummaryStatTileView: UIView {
    // MARK: Private state

    private var isForwardSource = false

    // MARK: UI

    private let iconImageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        iv.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .body)
        return iv
    }()

    private let valueLabel: UILabel = {
        let l = UILabel()
        // Tabular numerals so digits don't shift on updates.
        let descriptor = UIFontDescriptor
            .preferredFontDescriptor(withTextStyle: .title2)
            .addingAttributes([
                .featureSettings: [
                    [UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                     UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector],
                ],
            ])
        l.font = UIFont(descriptor: descriptor, size: 0)
        l.adjustsFontForContentSizeCategory = true
        l.textColor = .label
        l.textAlignment = .center
        l.adjustsFontSizeToFitWidth = true
        l.minimumScaleFactor = 0.6
        return l
    }()

    private let categoryLabel: UILabel = {
        let l = UILabel()
        l.font = .preferredFont(forTextStyle: .caption1)
        l.adjustsFontForContentSizeCategory = true
        l.textColor = .secondaryLabel
        l.textAlignment = .center
        l.numberOfLines = 2
        return l
    }()

    private let noteBadge: UILabel = {
        let l = UILabel()
        l.font = .preferredFont(forTextStyle: .caption2)
        l.adjustsFontForContentSizeCategory = true
        l.textAlignment = .center
        l.layer.masksToBounds = true
        l.layer.cornerRadius = 4
        return l
    }()

    // MARK: Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Layout

    private func setupLayout() {
        backgroundColor = Theme.secondaryGroupedBackground
        layer.cornerRadius = 12
        layer.masksToBounds = true

        let stack = UIStackView(arrangedSubviews: [iconImageView, valueLabel, categoryLabel, noteBadge])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 4
        stack.setCustomSpacing(2, after: categoryLabel)

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
    }

    // MARK: Configuration

    func configure(stat: SummaryStat) {
        isForwardSource = stat.source == .forward

        iconImageView.image = UIImage(systemName: stat.icon)
        applyTintColors()

        valueLabel.text = stat.value
        categoryLabel.text = stat.label

        if let note = stat.note {
            noteBadge.text = note
            noteBadge.isHidden = false
        } else {
            noteBadge.isHidden = true
        }

        // Accessibility: read as one atomic element.
        isAccessibilityElement = true
        var a11yParts = [stat.value, stat.label]
        if let note = stat.note { a11yParts.append(note) }
        accessibilityLabel = a11yParts.joined(separator: ", ")
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        applyTintColors()
    }

    // MARK: Private

    private func applyTintColors() {
        iconImageView.tintColor = isForwardSource ? tintColor : .secondaryLabel
        if !noteBadge.isHidden {
            noteBadge.textColor = tintColor
            noteBadge.backgroundColor = tintColor.withAlphaComponent(0.12)
        }
    }
}
