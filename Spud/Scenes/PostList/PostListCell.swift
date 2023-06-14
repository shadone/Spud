//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

class PostListCell: UITableViewCell {
    static let reuseIdentifier = "PostListCell"

    lazy var mainHorizontalStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.accessibilityIdentifier = "mainHorizontalStackView"
        return stackView
    }()

    lazy var thumbnailContainer: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.accessibilityIdentifier = "thumbnailContainer"
        return stackView
    }()

    lazy var thumbnailImageView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 8
        view.clipsToBounds = true
        view.backgroundColor = .lightGray
        view.accessibilityIdentifier = "thumbnailImageView"
        return view
    }()

    lazy var thumbnailBottomSpacerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.accessibilityIdentifier = "thumbnailBottomSpacerView"
        return view
    }()

    lazy var contentContainer: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 8
        stackView.accessibilityIdentifier = "contentVerticalStackView"
        return stackView
    }()

    lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Hello world"
        label.accessibilityIdentifier = "title"
        return label
    }()

    lazy var communityLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "science@lemmy.ml"
        label.accessibilityIdentifier = "community"
        return label
    }()

    lazy var contentBottomSpacerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.accessibilityIdentifier = "contentBottomSpacerView"
        return view
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        selectionStyle = .none

        contentView.addSubview(mainHorizontalStackView)

        mainHorizontalStackView.addArrangedSubview(thumbnailContainer)
        mainHorizontalStackView.addArrangedSubview(contentContainer)

        [
            thumbnailImageView,
            thumbnailBottomSpacerView,
        ].forEach(thumbnailContainer.addArrangedSubview)

        [
            titleLabel,
            communityLabel,
            contentBottomSpacerView,
        ].forEach(contentContainer.addArrangedSubview)

        NSLayoutConstraint.activate([
            mainHorizontalStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            mainHorizontalStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            mainHorizontalStackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            mainHorizontalStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),

            thumbnailImageView.widthAnchor.constraint(equalToConstant: 64),
            thumbnailImageView.heightAnchor.constraint(equalToConstant: 64),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
