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
final class FeedLoadingSkeletonView: SkeletonView {
    private let stack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    /// Caption pinned near the bottom, shown only once the load crosses the
    /// slow-connection threshold. Hidden by default and on `stopAnimating()`.
    private lazy var slowLabel: UILabel = {
        let label = UILabel()
        label.text = NSLocalizedString("Still loading… slow connection", comment: "Feed slow-load hint")
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false

        addSubview(stack)
        addSubview(slowLabel)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),

            slowLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            slowLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            slowLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            slowLabel.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -24),
        ])

        for _ in 0..<8 {
            stack.addArrangedSubview(makeRow())
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setShowsSlowHint(_ shows: Bool) {
        slowLabel.isHidden = !shows
    }

    override func stopAnimating() {
        super.stopAnimating()
        slowLabel.isHidden = true
    }

    private func makeRow() -> UIView {
        let thumbnail = Self.bar(height: 56)
        thumbnail.layer.cornerRadius = 9
        NSLayoutConstraint.activate([thumbnail.widthAnchor.constraint(equalToConstant: 56)])

        let textColumn = UIStackView()
        textColumn.axis = .vertical
        textColumn.alignment = .leading
        textColumn.spacing = 7

        let line1 = Self.bar(height: 13)
        let line2 = Self.bar(height: 13)
        let line3 = Self.bar(height: 11)
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
}
