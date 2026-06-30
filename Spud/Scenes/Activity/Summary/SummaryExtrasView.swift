//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SpudUIKit
import UIKit

// MARK: - SummaryExtraTileView

/// A compact summary tile for streak, top community, or busiest time.
@MainActor
private final class SummaryExtraTileView: UIView {
    // MARK: UI

    private let iconImageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        iv.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .footnote)
        iv.tintColor = .secondaryLabel
        return iv
    }()

    private let valueLabel: UILabel = {
        let l = UILabel()
        l.font = .preferredFont(forTextStyle: .callout)
        l.adjustsFontForContentSizeCategory = true
        l.textColor = .label
        l.textAlignment = .center
        l.numberOfLines = 2
        l.adjustsFontSizeToFitWidth = true
        l.minimumScaleFactor = 0.7
        return l
    }()

    private let captionLabel: UILabel = {
        let l = UILabel()
        l.font = .preferredFont(forTextStyle: .caption2)
        l.adjustsFontForContentSizeCategory = true
        l.textColor = .secondaryLabel
        l.textAlignment = .center
        l.numberOfLines = 1
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

        let stack = UIStackView(arrangedSubviews: [iconImageView, valueLabel, captionLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 4

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
    }

    // MARK: Configuration

    func configure(icon: String, value: String, caption: String) {
        iconImageView.image = UIImage(systemName: icon)
        valueLabel.text = value.isEmpty ? "—" : value
        captionLabel.text = caption

        isAccessibilityElement = true
        accessibilityLabel = "\(caption), \(value.isEmpty ? "none" : value)"
    }
}

// MARK: - SummaryExtrasView

/// A 3-column row of extra insight tiles: current streak, top community, and
/// busiest time-of-day band.
@MainActor
final class SummaryExtrasView: UIView {
    // MARK: Private

    private let streakTile = SummaryExtraTileView()
    private let communityTile = SummaryExtraTileView()
    private let busiestTile = SummaryExtraTileView()

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
        let row = UIStackView(arrangedSubviews: [streakTile, communityTile, busiestTile])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.axis = .horizontal
        row.spacing = 8
        row.distribution = .fillEqually

        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    // MARK: Configuration

    func configure(extras: SummaryExtras) {
        // Streak
        let streakValue: String
        if extras.streakDays == 0 {
            streakValue = ""
        } else if extras.streakDays == 1 {
            streakValue = NSLocalizedString("1 day", comment: "Streak 1 day")
        } else {
            streakValue = String(
                format: NSLocalizedString("%d days", comment: "Streak N days"),
                extras.streakDays
            )
        }
        streakTile.configure(
            icon: "flame",
            value: streakValue,
            caption: NSLocalizedString("Streak", comment: "Extras streak tile caption")
        )

        // Top community
        communityTile.configure(
            icon: "person.3",
            value: extras.topCommunity ?? "",
            caption: NSLocalizedString("Top community", comment: "Extras top community tile caption")
        )

        // Busiest time
        busiestTile.configure(
            icon: "clock",
            value: extras.busiest ?? "",
            caption: NSLocalizedString("Busiest time", comment: "Extras busiest time tile caption")
        )
    }
}
