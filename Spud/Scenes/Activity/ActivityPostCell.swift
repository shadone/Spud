//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import UIKit

class ActivityPostCell: UITableViewCell {
    static let reuseIdentifier = "ActivityPostCell"

    // MARK: UI

    private let actionHeader = ActivityActionHeaderView()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .preferredFont(forTextStyle: .body)
        l.textColor = .label
        l.numberOfLines = 3
        return l
    }()

    private let subtitleLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .preferredFont(forTextStyle: .caption1)
        l.textColor = .secondaryLabel
        l.numberOfLines = 1
        return l
    }()

    // MARK: Functions

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with item: ActivityItem, post: PostListRow) {
        actionHeader.configure(act: item.act, occurredAt: item.occurredAt)
        titleLabel.text = post.title
        subtitleLabel.text = subtitleText(post: post)
    }

    // MARK: Private

    private func setup() {
        actionHeader.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [actionHeader, titleLabel, subtitleLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 6

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
        ])
    }

    private func subtitleText(post: PostListRow) -> String {
        let score = post.score >= 0 ? "▲ \(post.score)" : "▼ \(abs(post.score))"
        let comments = String(
            format: NSLocalizedString("%lld comments", comment: "Post comment count"),
            post.numberOfComments
        )
        return "\(post.communityName) · \(score) · \(comments)"
    }
}
