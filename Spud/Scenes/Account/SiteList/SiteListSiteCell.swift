//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import Foundation
import SpudDataKit
import UIKit

class SiteListSiteCell: UITableViewCell {
    static let reuseIdentifier = "SiteListSiteCell"

    // MARK: UI Properties

    lazy var mainHorizontalStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.accessibilityIdentifier = "mainHorizontalStackView"

        let subviews = [
            iconContainer,
            contentContainer,
        ]
        for view in subviews {
            stackView.addArrangedSubview(view)
        }

        return stackView
    }()

    lazy var iconContainer: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.accessibilityIdentifier = "iconContainer"
        return stackView
    }()

    lazy var iconView: SiteListIconImageView = {
        let view = SiteListIconImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    lazy var iconTextView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        return imageView
    }()

    lazy var iconBottomSpacerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.accessibilityIdentifier = "iconBottomSpacerView"
        return view
    }()

    lazy var contentContainer: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 0
        stackView.accessibilityIdentifier = "contentVerticalStackView"

        let contentBottomSpacerView: UIView = {
            let view = UIView()
            view.translatesAutoresizingMaskIntoConstraints = false
            view.setContentHuggingPriority(.defaultLow, for: .vertical)
            return view
        }()

        let subviews = [
            titleLabel,
            subtitleLabel,
            contentBottomSpacerView,
        ]
        for view in subviews {
            stackView.addArrangedSubview(view)
        }

        stackView.setCustomSpacing(8, after: titleLabel)

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

        contentView.addSubview(mainHorizontalStackView)

        let subviews = [
            iconView,
            iconBottomSpacerView,
        ]
        for view in subviews {
            iconContainer.addArrangedSubview(view)
        }

        NSLayoutConstraint.activate([
            mainHorizontalStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            mainHorizontalStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            mainHorizontalStackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            mainHorizontalStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),

            iconView.widthAnchor.constraint(equalToConstant: 40),
            iconView.heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        disposables.removeAll()
        iconView.prepareForReuse()
    }

    func configure(with viewModel: SiteListSiteViewModel) {
        viewModel.title
            .map { NSAttributedString($0) }
            .wrapInOptional()
            .assign(to: \.attributedText, on: titleLabel)
            .store(in: &disposables)

        viewModel.descriptionText
            .map { NSAttributedString($0) }
            .wrapInOptional()
            .assign(to: \.attributedText, on: subtitleLabel)
            .store(in: &disposables)

        viewModel.icon
            .map { imageLoadingState in
                switch imageLoadingState {
                case let .ready(image):
                    return .image(image)
                case .failure:
                    return .failure
                case .loading:
                    return .none
                case .none:
                    return .noIcon
                }
            }
            .assign(to: \.iconType, on: iconView)
            .store(in: &disposables)
    }
}
