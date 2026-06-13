//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// A loading placeholder for the feed: a column of skeleton rows (a thumbnail
/// block plus three text bars) that gently pulse. Shown as the table background
/// during the initial fetch — before the first snapshot — matching the design's
/// Loading state, so the feed never flashes blank.
final class FeedLoadingSkeletonView: UIView {
    private let stack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        for _ in 0..<8 {
            stack.addArrangedSubview(makeRow())
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Starts the pulse, unless Reduce Motion is on (then the bars stay static).
    func startAnimating() {
        layer.removeAnimation(forKey: "pulse")
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.45
        pulse.duration = 0.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(pulse, forKey: "pulse")
    }

    func stopAnimating() {
        layer.removeAnimation(forKey: "pulse")
    }

    private func makeRow() -> UIView {
        let thumbnail = bar(height: 56)
        thumbnail.layer.cornerRadius = 9
        NSLayoutConstraint.activate([thumbnail.widthAnchor.constraint(equalToConstant: 56)])

        let textColumn = UIStackView()
        textColumn.axis = .vertical
        textColumn.alignment = .leading
        textColumn.spacing = 7

        let line1 = bar(height: 13)
        let line2 = bar(height: 13)
        let line3 = bar(height: 11)
        textColumn.addArrangedSubview(line1)
        textColumn.addArrangedSubview(line2)
        textColumn.addArrangedSubview(line3)
        textColumn.setCustomSpacing(11, after: line2)

        let row = UIStackView(arrangedSubviews: [thumbnail, textColumn])
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = 11

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        row.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)

        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator.withAlphaComponent(0.5)
        container.addSubview(separator)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: container.topAnchor, constant: 11),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -11),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),

            // Two full-ish lines and a shorter third, like a wrapped title + meta.
            line1.widthAnchor.constraint(equalTo: textColumn.widthAnchor),
            line2.widthAnchor.constraint(equalTo: textColumn.widthAnchor, multiplier: 0.7),
            line3.widthAnchor.constraint(equalToConstant: 150),

            separator.heightAnchor.constraint(equalToConstant: 0.5),
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    private func bar(height: CGFloat) -> UIView {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .tertiarySystemFill
        view.layer.cornerRadius = min(height / 2, 6)
        view.layer.cornerCurve = .continuous
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }
}
