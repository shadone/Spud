//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import Foundation
import UIKit

class AccountListAccountCell: UITableViewCell {
    static let reuseIdentifier = "AccountListAccountCell"

    // MARK: UI Properties

    lazy var contentContainer: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 4
        stackView.accessibilityIdentifier = "contentVerticalStackView"

        let contentBottomSpacerView: UIView = {
            let view = UIView()
            view.translatesAutoresizingMaskIntoConstraints = false
            view.setContentHuggingPriority(.defaultLow, for: .vertical)
            return view
        }()

        [
            titleLabel,
            subtitleLabel,
            contentBottomSpacerView,
        ].forEach(stackView.addArrangedSubview)

        return stackView
    }()

    lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.accessibilityIdentifier = "title"
        return label
    }()

    lazy var subtitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.accessibilityIdentifier = "subtitle"
        label.numberOfLines = 0
        return label
    }()

    // MARK: Private

    private var disposables = Set<AnyCancellable>()

    // MARK: Functions

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        selectionStyle = .none

        contentView.addSubview(contentContainer)

        NSLayoutConstraint.activate([
            contentContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            contentContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            contentContainer.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            contentContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        disposables.removeAll()
    }

    func configure(with viewModel: AccountListAccountViewModel) {
        viewModel.title
            .map { NSAttributedString($0) }
            .wrapInOptional()
            .assign(to: \.attributedText, on: titleLabel)
            .store(in: &disposables)

        viewModel.subtitle
            .assign(to: \.attributedText, on: subtitleLabel)
            .store(in: &disposables)

        viewModel.defaultAccountAccessoryType
            .assign(to: \.accessoryType, on: self)
            .store(in: &disposables)
    }
}
