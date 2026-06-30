//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SpudUIKit
import UIKit

/// A horizontal strip showing the account holder's avatar placeholder, display
/// name, joined date, and cake-day. Sits at the top of the Summary dashboard.
@MainActor
final class SummaryIdentityStripView: UIView {
    // MARK: UI

    private let avatarView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = .secondarySystemFill
        v.layer.cornerRadius = 22
        v.layer.masksToBounds = true
        // Placeholder person SF symbol centered inside.
        let img = UIImageView(image: UIImage(systemName: "person.circle.fill"))
        img.translatesAutoresizingMaskIntoConstraints = false
        img.tintColor = .systemGray3
        img.contentMode = .scaleAspectFit
        v.addSubview(img)
        NSLayoutConstraint.activate([
            img.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            img.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            img.topAnchor.constraint(equalTo: v.topAnchor),
            img.bottomAnchor.constraint(equalTo: v.bottomAnchor),
        ])
        return v
    }()

    private let nameLabel: UILabel = {
        let l = UILabel()
        l.font = .preferredFont(forTextStyle: .headline)
        l.adjustsFontForContentSizeCategory = true
        l.textColor = .label
        l.numberOfLines = 1
        return l
    }()

    private let metaLabel: UILabel = {
        let l = UILabel()
        l.font = .preferredFont(forTextStyle: .footnote)
        l.adjustsFontForContentSizeCategory = true
        l.textColor = .secondaryLabel
        l.numberOfLines = 0
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
        let textStack = UIStackView(arrangedSubviews: [nameLabel, metaLabel])
        textStack.axis = .vertical
        textStack.spacing = 2

        let row = UIStackView(arrangedSubviews: [avatarView, textStack])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center

        addSubview(row)
        NSLayoutConstraint.activate([
            avatarView.widthAnchor.constraint(equalToConstant: 44),
            avatarView.heightAnchor.constraint(equalToConstant: 44),

            row.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])
    }

    // MARK: Configuration

    func configure(stats: SummaryStats) {
        nameLabel.text = stats.name.isEmpty ? NSLocalizedString("Account", comment: "Summary identity placeholder name") : stats.name

        var meta = ""
        if !stats.joined.isEmpty {
            meta = String(
                format: NSLocalizedString("Joined %@ · cake-day %@", comment: "Summary identity joined + cake-day"),
                stats.joined,
                stats.cakeDay
            )
        }
        metaLabel.text = meta
        metaLabel.isHidden = meta.isEmpty

        // Accessibility: treat the whole strip as one element.
        isAccessibilityElement = true
        accessibilityLabel = [nameLabel.text, metaLabel.text]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}
