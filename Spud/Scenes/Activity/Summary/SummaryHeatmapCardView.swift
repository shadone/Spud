//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SpudUIKit
import UIKit

/// The full "Activity over time" card: title + total count, metric segmented
/// control (All/Reads/Votes), the heatmap grid, and the empty-votes note.
@MainActor
final class SummaryHeatmapCardView: UIView {
    // MARK: Callbacks

    /// Called when the user picks a different metric segment.
    var onMetricChanged: ((HeatmapMetric) -> Void)?

    // MARK: UI

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .preferredFont(forTextStyle: .headline)
        l.adjustsFontForContentSizeCategory = true
        l.textColor = .label
        l.text = NSLocalizedString("Activity over time", comment: "Heatmap card title")
        return l
    }()

    private let totalLabel: UILabel = {
        let l = UILabel()
        l.font = .preferredFont(forTextStyle: .subheadline)
        l.adjustsFontForContentSizeCategory = true
        l.textColor = .secondaryLabel
        return l
    }()

    private lazy var metricControl: UISegmentedControl = {
        let items = [
            NSLocalizedString("All", comment: "Heatmap metric all"),
            NSLocalizedString("Reads", comment: "Heatmap metric reads"),
            NSLocalizedString("Votes", comment: "Heatmap metric votes"),
        ]
        let sc = UISegmentedControl(items: items)
        sc.selectedSegmentIndex = 0
        sc.addTarget(self, action: #selector(metricSegmentChanged), for: .valueChanged)
        return sc
    }()

    private let heatmapView = SummaryHeatmapView()

    private let votesEmptyNoteLabel: UILabel = {
        let l = UILabel()
        l.font = .preferredFont(forTextStyle: .footnote)
        l.adjustsFontForContentSizeCategory = true
        l.textColor = .secondaryLabel
        l.numberOfLines = 0
        l.textAlignment = .center
        l.text = NSLocalizedString(
            "Votes appear here from now on. Nothing to plot yet.",
            comment: "Heatmap votes empty note"
        )
        l.isHidden = true
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
        layer.cornerRadius = 16
        layer.masksToBounds = true

        let titleRow = UIStackView(arrangedSubviews: [titleLabel, UIView(), totalLabel])
        titleRow.axis = .horizontal
        titleRow.spacing = 8
        titleRow.alignment = .firstBaseline

        heatmapView.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [
            titleRow,
            metricControl,
            heatmapView,
            votesEmptyNoteLabel,
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .fill

        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),

            heatmapView.heightAnchor.constraint(equalToConstant: heatmapView.intrinsicContentSize.height),
        ])
    }

    // MARK: Configuration

    func configure(series: HeatmapSeries) {
        // Total label
        let total = series.total
        totalLabel.text = String(
            format: NSLocalizedString("%@ total", comment: "Heatmap total count label"),
            formatCount(total)
        )

        // Heatmap grid
        heatmapView.configure(series: series)

        // Sync segmented control without re-firing the action.
        let segIndex = HeatmapMetric.allCases.firstIndex(of: series.metric) ?? 0
        metricControl.selectedSegmentIndex = segIndex

        // Votes-empty note: show when the votes metric has zero total.
        let showVotesNote = series.metric == .votes && series.total == 0
        votesEmptyNoteLabel.isHidden = !showVotesNote
    }

    // MARK: Actions

    @objc private func metricSegmentChanged() {
        let metrics = HeatmapMetric.allCases
        let index = metricControl.selectedSegmentIndex
        guard index >= 0, index < metrics.count else { return }
        onMetricChanged?(metrics[index])
    }

    // MARK: Private

    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            let v = Double(count) / 1_000_000
            return String(format: "%.1fM", v)
        } else if count >= 1_000 {
            let v = Double(count) / 1_000
            return String(format: "%.1fK", v)
        }
        return "\(count)"
    }
}
