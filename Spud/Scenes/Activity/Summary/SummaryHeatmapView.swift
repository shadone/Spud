//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import UIKit

// MARK: - HeatmapCellView

/// A single square cell in the contribution heatmap grid.
///
/// Color encodes activity intensity using five alpha steps of the view
/// hierarchy's `tintColor`. For accessibility, buckets 3 and 4 also receive
/// a contrasting inner ring so intensity is distinguishable without relying
/// solely on hue or saturation.
@MainActor
private final class HeatmapCellView: UIView {
    static let size: CGFloat = 13
    static let cornerRadius: CGFloat = 3

    private var bucket: Int = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = Self.cornerRadius
        layer.masksToBounds = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(day: HeatmapDay, dateFormatter: DateFormatter) {
        bucket = day.bucket
        applyColors()

        // Accessibility
        isAccessibilityElement = true
        let dateStr = dateFormatter.string(from: day.date)
        if day.isEmpty {
            accessibilityLabel = String(
                format: NSLocalizedString("%@, no activity", comment: "Heatmap cell accessibility label (no activity)"),
                dateStr
            )
        } else {
            accessibilityLabel = String(
                format: NSLocalizedString("%@, %d activities", comment: "Heatmap cell accessibility label"),
                dateStr,
                day.count
            )
        }
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        applyColors()
    }

    private func applyColors() {
        // Fill color: escalating tint alpha for buckets 1-4; fill for 0.
        switch bucket {
        case 0:
            backgroundColor = .secondarySystemFill
            layer.borderWidth = 0
        case 1:
            backgroundColor = tintColor.withAlphaComponent(0.20)
            layer.borderWidth = 0
        case 2:
            backgroundColor = tintColor.withAlphaComponent(0.45)
            layer.borderWidth = 0
        case 3:
            // Non-color intensity cue: inner ring border for high buckets.
            backgroundColor = tintColor.withAlphaComponent(0.70)
            layer.borderWidth = 1.5
            layer.borderColor = tintColor.withAlphaComponent(0.35).cgColor
        default: // 4
            backgroundColor = tintColor
            layer.borderWidth = 1.5
            layer.borderColor = tintColor.withAlphaComponent(0.50).cgColor
        }
    }
}

// MARK: - SummaryHeatmapView

/// The 18 × 7 contribution heatmap grid with month labels, M/W/F day
/// labels, and a Less/More legend.
///
/// The view uses a fixed cell size and manual `layoutSubviews` positioning.
/// Its `intrinsicContentSize` accounts for the fixed grid dimensions so Auto
/// Layout containers size it correctly.
@MainActor
final class SummaryHeatmapView: UIView {
    // MARK: Layout constants

    private static let cellSize: CGFloat = HeatmapCellView.size
    private static let cellGap: CGFloat = 2
    private static let dayLabelWidth: CGFloat = 20
    private static let dayLabelGap: CGFloat = 4
    private static let monthLabelHeight: CGFloat = 14
    private static let monthLabelGap: CGFloat = 4
    private static let legendHeight: CGFloat = 18
    private static let legendGap: CGFloat = 8
    private static let weeksCount = 18
    private static let daysPerWeek = 7

    private static var gridWidth: CGFloat {
        CGFloat(weeksCount) * cellSize + CGFloat(weeksCount - 1) * cellGap
    }

    private static var gridHeight: CGFloat {
        CGFloat(daysPerWeek) * cellSize + CGFloat(daysPerWeek - 1) * cellGap
    }

    private static var totalWidth: CGFloat {
        dayLabelWidth + dayLabelGap + gridWidth
    }

    private static var totalHeight: CGFloat {
        monthLabelHeight + monthLabelGap + gridHeight + legendGap + legendHeight
    }

    // MARK: Subviews

    // cells[weekIndex][dayIndex]: weekIndex 0 = oldest, dayIndex 0 = Monday.
    private var cells: [[HeatmapCellView]] = []
    private var monthLabels: [UILabel] = []
    private let mondayLabel = SummaryHeatmapView.dayLabel("M")
    private let wednesdayLabel = SummaryHeatmapView.dayLabel("W")
    private let fridayLabel = SummaryHeatmapView.dayLabel("F")
    private let legendView = SummaryHeatmapView.makeLegend()

    // MARK: Formatters

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f
    }()

    // MARK: Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Setup

    private func setupSubviews() {
        // Build cells
        cells = (0..<Self.weeksCount).map { _ in
            (0..<Self.daysPerWeek).map { _ in
                let cell = HeatmapCellView()
                cell.frame.size = CGSize(width: Self.cellSize, height: Self.cellSize)
                addSubview(cell)
                return cell
            }
        }

        // Day labels
        [mondayLabel, wednesdayLabel, fridayLabel].forEach { addSubview($0) }

        // Legend
        legendView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(legendView)
    }

    // MARK: Intrinsic size

    override var intrinsicContentSize: CGSize {
        CGSize(width: Self.totalWidth, height: Self.totalHeight)
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        positionSubviews()
    }

    private func positionSubviews() {
        let gridTop = Self.monthLabelHeight + Self.monthLabelGap
        let gridLeft = Self.dayLabelWidth + Self.dayLabelGap

        // Position cells
        for (weekIndex, weekCells) in cells.enumerated() {
            let x = gridLeft + CGFloat(weekIndex) * (Self.cellSize + Self.cellGap)
            for (dayIndex, cell) in weekCells.enumerated() {
                let y = gridTop + CGFloat(dayIndex) * (Self.cellSize + Self.cellGap)
                cell.frame = CGRect(x: x, y: y, width: Self.cellSize, height: Self.cellSize)
            }
        }

        /// Day labels: centred vertically on Mon/Wed/Fri rows (rows 0/2/4).
        func yForDay(_ index: Int) -> CGFloat {
            gridTop + CGFloat(index) * (Self.cellSize + Self.cellGap)
        }

        let labelWidth = Self.dayLabelWidth
        let dayLabelSize = CGSize(width: labelWidth, height: Self.cellSize)
        mondayLabel.frame = CGRect(origin: CGPoint(x: 0, y: yForDay(0)), size: dayLabelSize)
        wednesdayLabel.frame = CGRect(origin: CGPoint(x: 0, y: yForDay(2)), size: dayLabelSize)
        fridayLabel.frame = CGRect(origin: CGPoint(x: 0, y: yForDay(4)), size: dayLabelSize)

        // Legend: sits below the grid, full width of the grid area.
        let legendY = gridTop + Self.gridHeight + Self.legendGap
        legendView.frame = CGRect(
            x: gridLeft,
            y: legendY,
            width: Self.gridWidth,
            height: Self.legendHeight
        )
    }

    // MARK: Configuration

    func configure(series: HeatmapSeries) {
        guard series.weeks.count == Self.weeksCount else { return }

        // Update cells
        for (weekIndex, week) in series.weeks.enumerated() {
            guard weekIndex < cells.count else { break }
            for (dayIndex, day) in week.enumerated() {
                guard dayIndex < cells[weekIndex].count else { break }
                cells[weekIndex][dayIndex].configure(day: day, dateFormatter: Self.dateFormatter)
            }
        }

        // Rebuild month labels
        monthLabels.forEach { $0.removeFromSuperview() }
        monthLabels = []
        buildMonthLabels(weeks: series.weeks)

        setNeedsLayout()
    }

    // MARK: Private

    private func buildMonthLabels(weeks: [[HeatmapDay]]) {
        let gridLeft = Self.dayLabelWidth + Self.dayLabelGap
        var lastMonth: Int? = nil

        for (weekIndex, week) in weeks.enumerated() {
            guard let monday = week.first else { continue }
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "UTC")!
            let month = cal.component(.month, from: monday.date)

            if month != lastMonth {
                lastMonth = month
                let label = UILabel()
                label.font = .preferredFont(forTextStyle: .caption2)
                label.adjustsFontForContentSizeCategory = true
                label.textColor = .secondaryLabel
                label.text = Self.monthFormatter.string(from: monday.date)
                label.sizeToFit()

                let x = gridLeft + CGFloat(weekIndex) * (Self.cellSize + Self.cellGap)
                label.frame = CGRect(
                    x: x,
                    y: 0,
                    width: max(label.frame.width, Self.cellSize),
                    height: Self.monthLabelHeight
                )
                addSubview(label)
                monthLabels.append(label)
            }
        }
    }

    // MARK: Factory helpers

    private static func dayLabel(_ text: String) -> UILabel {
        let l = UILabel()
        l.font = .preferredFont(forTextStyle: .caption2)
        l.adjustsFontForContentSizeCategory = true
        l.textColor = .secondaryLabel
        l.text = text
        l.textAlignment = .right
        return l
    }

    private static func makeLegend() -> UIView {
        let lessLabel = UILabel()
        lessLabel.font = .preferredFont(forTextStyle: .caption2)
        lessLabel.adjustsFontForContentSizeCategory = true
        lessLabel.textColor = .secondaryLabel
        lessLabel.text = NSLocalizedString("Less", comment: "Heatmap legend less label")

        let moreLabel = UILabel()
        moreLabel.font = .preferredFont(forTextStyle: .caption2)
        moreLabel.adjustsFontForContentSizeCategory = true
        moreLabel.textColor = .secondaryLabel
        moreLabel.text = NSLocalizedString("More", comment: "Heatmap legend more label")

        // Five small colored squares representing buckets 0-4.
        let squares: [UIView] = (0..<5).map { _ in
            let v = UIView()
            v.layer.cornerRadius = 2
            v.layer.masksToBounds = true
            v.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                v.widthAnchor.constraint(equalToConstant: 10),
                v.heightAnchor.constraint(equalToConstant: 10),
            ])
            return v
        }

        let legend = SummaryHeatmapLegendView(
            lessLabel: lessLabel,
            moreLabel: moreLabel,
            squares: squares
        )
        legend.translatesAutoresizingMaskIntoConstraints = false
        return legend
    }
}

// MARK: - SummaryHeatmapLegendView

/// A compact Less ■ ■ ■ ■ ■ More row that updates square colors when tint changes.
@MainActor
private final class SummaryHeatmapLegendView: UIView {
    private let lessLabel: UILabel
    private let moreLabel: UILabel
    private let squares: [UIView]

    init(lessLabel: UILabel, moreLabel: UILabel, squares: [UIView]) {
        self.lessLabel = lessLabel
        self.moreLabel = moreLabel
        self.squares = squares
        super.init(frame: .zero)
        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupLayout() {
        var arranged: [UIView] = [lessLabel]
        arranged += squares
        arranged.append(moreLabel)

        let stack = UIStackView(arrangedSubviews: arranged)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 4
        stack.alignment = .center
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        applySquareColors()
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        applySquareColors()
    }

    private func applySquareColors() {
        let alphas: [CGFloat] = [0, 0.20, 0.45, 0.70, 1.0]
        for (index, square) in squares.enumerated() {
            if index == 0 {
                square.backgroundColor = .secondarySystemFill
            } else {
                square.backgroundColor = tintColor.withAlphaComponent(alphas[index])
            }
        }
    }
}
