//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import UIKit

class ActivityCommentCell: UITableViewCell {
    static let reuseIdentifier = "ActivityCommentCell"

    // MARK: UI

    private let actionHeader = ActivityActionHeaderView()

    private let bodyLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .preferredFont(forTextStyle: .body)
        l.textColor = .label
        l.numberOfLines = 3
        return l
    }()

    private let parentPostLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .preferredFont(forTextStyle: .caption1)
        l.textColor = .secondaryLabel
        l.numberOfLines = 1
        return l
    }()

    private let scoreLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .preferredFont(forTextStyle: .caption1)
        l.textColor = .secondaryLabel
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

    func configure(with item: ActivityItem, comment: ActivityCommentRow) {
        actionHeader.configure(act: item.act, occurredAt: item.occurredAt)
        bodyLabel.text = comment.body
        parentPostLabel.text = "\(comment.communityName) · \(comment.parentPostTitle)"
        scoreLabel.text = scoreText(comment.score)
    }

    // MARK: Private

    private func setup() {
        actionHeader.translatesAutoresizingMaskIntoConstraints = false

        let metaStack = UIStackView(arrangedSubviews: [actionHeader, scoreLabel])
        metaStack.translatesAutoresizingMaskIntoConstraints = false
        metaStack.axis = .horizontal
        metaStack.spacing = 8
        metaStack.alignment = .center

        let stack = UIStackView(arrangedSubviews: [metaStack, bodyLabel, parentPostLabel])
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

    private func scoreText(_ score: Int64) -> String {
        if score >= 0 {
            return "▲ \(score)"
        } else {
            return "▼ \(abs(score))"
        }
    }
}
