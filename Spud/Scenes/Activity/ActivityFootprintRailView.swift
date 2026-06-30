//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudUIKit
import UIKit

/// The iPhone "Your footprint" rail: a tappable card shown above the Activity
/// timeline in its default glance state. It mirrors the first four Summary stat
/// tiles (Posts / Comments / Saved / Votes) as a one-line glance and routes a
/// tap to the full Summary dashboard.
///
/// Layout is pure Auto Layout — the card wraps its content (header row over a
/// row of up to four stat columns) so it grows with Dynamic Type rather than
/// clipping at a fixed height. The whole card is a single accessibility element
/// with the `.button` trait: VoiceOver reads one combined label and activates
/// `onTapSummary`, instead of exposing five stray labels.
@MainActor
final class ActivityFootprintRailView: UIView {
    /// Invoked when the card is tapped (or activated via VoiceOver).
    var onTapSummary: (() -> Void)?

    // MARK: Private state

    private var accentColor: UIColor = .tintColor
    private var stats: [FootprintStat] = []

    // MARK: UI

    private let cardView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = Theme.secondaryBackground
        v.layer.cornerRadius = 14
        v.layer.cornerCurve = .continuous
        v.layer.borderWidth = 1.0 / UIScreen.main.scale
        v.layer.borderColor = UIColor.separator.cgColor
        v.layoutMargins = UIEdgeInsets(top: 11, left: 13, bottom: 11, right: 13)
        return v
    }()

    private let glyphImageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        iv.image = UIImage(systemName: "chart.bar.xaxis")
        iv.setContentHuggingPriority(.required, for: .horizontal)
        iv.setContentCompressionResistancePriority(.required, for: .horizontal)
        return iv
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = UIFontMetrics(forTextStyle: .subheadline)
            .scaledFont(for: .systemFont(ofSize: 13, weight: .bold))
        l.adjustsFontForContentSizeCategory = true
        l.textColor = .label
        l.text = NSLocalizedString("Your footprint", comment: "Activity footprint rail title")
        return l
    }()

    private let summaryLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = UIFontMetrics(forTextStyle: .caption1)
            .scaledFont(for: .systemFont(ofSize: 12, weight: .semibold))
        l.adjustsFontForContentSizeCategory = true
        l.text = NSLocalizedString("Summary \u{203A}", comment: "Activity footprint rail: link to the Summary dashboard")
        l.setContentHuggingPriority(.required, for: .horizontal)
        l.setContentCompressionResistancePriority(.required, for: .horizontal)
        return l
    }()

    private let statsRow: UIStackView = {
        let s = UIStackView()
        s.translatesAutoresizingMaskIntoConstraints = false
        s.axis = .horizontal
        s.distribution = .fillEqually
        s.alignment = .top
        s.spacing = 8
        return s
    }()

    // MARK: Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Setup

    private func setup() {
        directionalLayoutMargins = NSDirectionalEdgeInsets(top: 4, leading: 16, bottom: 10, trailing: 16)

        let headerRow = UIStackView(arrangedSubviews: [glyphImageView, titleLabel, summaryLabel])
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        headerRow.axis = .horizontal
        headerRow.alignment = .firstBaseline
        headerRow.spacing = 6
        // The title takes the slack so "Summary >" hugs the trailing edge.
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let contentStack = UIStackView(arrangedSubviews: [headerRow, statsRow])
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 8

        addSubview(cardView)
        cardView.addSubview(contentStack)

        let marginGuide = layoutMarginsGuide
        let cardMargins = cardView.layoutMarginsGuide

        let cardBottomWrap = cardView.bottomAnchor.constraint(equalTo: marginGuide.bottomAnchor)
        cardBottomWrap.priority = .defaultLow

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: marginGuide.topAnchor),
            cardView.leadingAnchor.constraint(equalTo: marginGuide.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: marginGuide.trailingAnchor),
            cardView.bottomAnchor.constraint(lessThanOrEqualTo: marginGuide.bottomAnchor),
            cardBottomWrap,

            contentStack.topAnchor.constraint(equalTo: cardMargins.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: cardMargins.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: cardMargins.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: cardMargins.bottomAnchor),
        ])

        // Glyph baseline-aligns with the title.
        glyphImageView.firstBaselineAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor).isActive = true

        let tap = UITapGestureRecognizer(target: self, action: #selector(cardTapped))
        addGestureRecognizer(tap)

        // One accessibility element for the whole card.
        isAccessibilityElement = true
        accessibilityTraits = .button

        applyAccent()
    }

    // MARK: Configuration

    /// Populates the rail with up to four quick stats and the active accent
    /// color. Extra stats are ignored (the rail shows at most four columns).
    func configure(stats: [FootprintStat], accent: UIColor) {
        self.stats = stats
        accentColor = accent
        applyAccent()
        rebuildColumns()
        updateAccessibility()
    }

    // MARK: Private

    @objc
    private func cardTapped() {
        onTapSummary?()
    }

    override func accessibilityActivate() -> Bool {
        onTapSummary?()
        return true
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        // The border color is a CGColor, so it doesn't re-resolve on a
        // light/dark switch on its own.
        cardView.layer.borderColor = UIColor.separator.resolvedColor(with: traitCollection).cgColor
    }

    private func applyAccent() {
        glyphImageView.tintColor = accentColor
        summaryLabel.textColor = accentColor
    }

    private func rebuildColumns() {
        for view in statsRow.arrangedSubviews {
            statsRow.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for stat in stats.prefix(4) {
            statsRow.addArrangedSubview(makeColumn(stat: stat))
        }
    }

    private func makeColumn(stat: FootprintStat) -> UIView {
        let valueLabel = UILabel()
        let descriptor = UIFont.monospacedDigitSystemFont(ofSize: 17, weight: .heavy)
        valueLabel.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: descriptor)
        valueLabel.adjustsFontForContentSizeCategory = true
        valueLabel.textColor = .label
        valueLabel.text = stat.value
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.6

        let labelLabel = UILabel()
        labelLabel.font = UIFontMetrics(forTextStyle: .caption2)
            .scaledFont(for: .systemFont(ofSize: 10, weight: .regular))
        labelLabel.adjustsFontForContentSizeCategory = true
        labelLabel.textColor = .secondaryLabel
        labelLabel.text = stat.label
        labelLabel.numberOfLines = 1

        let column = UIStackView(arrangedSubviews: [valueLabel, labelLabel])
        column.axis = .vertical
        column.alignment = .leading
        column.spacing = 1
        return column
    }

    private func updateAccessibility() {
        let title = NSLocalizedString("Your footprint", comment: "Activity footprint rail title")
        let parts = stats.prefix(4).map { "\(spokenValue($0.value)) \($0.label.lowercased())" }
        if parts.isEmpty {
            accessibilityLabel = title
        } else {
            accessibilityLabel = "\(title). \(parts.joined(separator: ", "))."
        }
        accessibilityHint = NSLocalizedString(
            "Opens your activity summary",
            comment: "Activity footprint rail VoiceOver hint"
        )
    }

    /// Expands an abbreviated display value into a spoken form for VoiceOver
    /// (e.g. "1.2k" -> "1.2 thousand", "5.0k" -> "5 thousand"). Operates on the
    /// already-formatted string; it does not recompute the stat.
    private func spokenValue(_ value: String) -> String {
        var digits = value
        var suffix = ""
        if digits.hasSuffix("k") {
            suffix = NSLocalizedString(" thousand", comment: "Spoken expansion of the 'k' abbreviation for VoiceOver")
            digits.removeLast()
        } else if digits.hasSuffix("M") {
            suffix = NSLocalizedString(" million", comment: "Spoken expansion of the 'M' abbreviation for VoiceOver")
            digits.removeLast()
        }
        if digits.hasSuffix(".0") {
            digits.removeLast(2)
        }
        return digits + suffix
    }
}
