//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import UIKit

class PostListPostCell: UITableViewCell {
    static let reuseIdentifier = "PostListPostCell"

    // MARK: Public

    var swipeActionConfiguration: SwipeActionView.Configuration? {
        get { swipeActionView.configuration }
        set { swipeActionView.configuration = newValue }
    }

    var swipeActionTriggered: ((SwipeActionView.ActionTrigger) -> Void)?

    // MARK: UI Properties

    lazy var mainHorizontalStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.accessibilityIdentifier = "mainHorizontalStackView"

        let subviews = [
            thumbnailContainer,
            contentContainer,
        ]
        for view in subviews {
            stackView.addArrangedSubview(view)
        }

        return stackView
    }()

    lazy var thumbnailContainer: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.accessibilityIdentifier = "thumbnailContainer"
        return stackView
    }()

    lazy var thumbnailView: PostListThumbnailImageView = {
        let view = PostListThumbnailImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
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
        return label
    }()

    lazy var swipeActionView: SwipeActionView = {
        let view = SwipeActionView(
            contentView: mainHorizontalStackView,
            margin: UIEdgeInsets(top: 16, left: 16, bottom: -16, right: -16),
            configuration: nil
        )
        view.translatesAutoresizingMaskIntoConstraints = false
        view.trigger = { [weak self] action in
            self?.swipeActionTriggered?(action)
        }
        return view
    }()

    // MARK: Private

    private var thumbnailLoadTask: Task<Void, Never>?

    // MARK: Functions

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        selectionStyle = .none

        contentView.addSubview(swipeActionView)

        let subviews = [
            thumbnailView,
            thumbnailBottomSpacerView,
        ]
        for view in subviews {
            thumbnailContainer.addArrangedSubview(view)
        }

        NSLayoutConstraint.activate([
            swipeActionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            swipeActionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            swipeActionView.topAnchor.constraint(equalTo: contentView.topAnchor),
            swipeActionView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            thumbnailView.widthAnchor.constraint(equalToConstant: 64),
            thumbnailView.heightAnchor.constraint(equalToConstant: 64),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        thumbnailLoadTask?.cancel()
        thumbnailLoadTask = nil
        thumbnailView.prepareForReuse()

        swipeActionConfiguration = nil
        swipeActionTriggered = nil
    }

    func configure(with viewModel: PostListPostViewModel, imageService: ImageServiceType) {
        titleLabel.attributedText = viewModel.title
        subtitleLabel.attributedText = viewModel.subtitle

        thumbnailLoadTask?.cancel()
        switch viewModel.thumbnail {
        case .text:
            thumbnailView.thumbnailType = .text
        case let .image(thumbnailUrl):
            thumbnailView.thumbnailType = .none
            thumbnailLoadTask = Task { [weak self] in
                for await state in imageService.fetch(thumbnailUrl) {
                    if Task.isCancelled { return }
                    guard let self else { return }
                    switch state {
                    case .loading:
                        thumbnailView.thumbnailType = .none
                    case .failure:
                        thumbnailView.thumbnailType = .imageFailure
                    case let .ready(image):
                        thumbnailView.thumbnailType = .image(image)
                    }
                }
            }
        }
    }
}
