//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

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
            statsLabel,
            contentBottomSpacerView,
        ]
        for view in subviews {
            stackView.addArrangedSubview(view)
        }

        stackView.setCustomSpacing(8, after: titleLabel)
        stackView.setCustomSpacing(4, after: subtitleLabel)

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

    lazy var statsLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.accessibilityIdentifier = "stats"
        label.numberOfLines = 0
        return label
    }()

    // MARK: Private

    private var iconObservationTask: Task<Void, Never>?

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

        iconObservationTask?.cancel()
        iconObservationTask = nil
        iconView.prepareForReuse()
    }

    func configure(with viewModel: SiteListSiteViewModel) {
        titleLabel.attributedText = NSAttributedString(viewModel.title)
        subtitleLabel.attributedText = NSAttributedString(viewModel.descriptionText)

        let stats = NSAttributedString(viewModel.statsText)
        statsLabel.attributedText = stats
        statsLabel.isHidden = stats.length == 0

        iconObservationTask?.cancel()
        iconObservationTask = Task { @MainActor [weak self, viewModel] in
            for await state in ObservationStream.values(of: { viewModel.iconState }) {
                self?.iconView.iconType = Self.iconType(from: state)
            }
        }
    }

    private static func iconType(from state: ImageLoadingState?) -> SiteListIconImageView.IconType {
        switch state {
        case let .ready(image):
            .image(image)
        case .failure:
            .failure
        case .loading:
            .none
        case .none:
            .noIcon
        }
    }

    deinit {
        iconObservationTask?.cancel()
    }
}
