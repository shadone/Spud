//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import UIKit

class PostListPostCell: UITableViewCell {
    static let reuseIdentifier = "PostListPostCell"

    // MARK: UI Properties

    lazy var mainHorizontalStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.accessibilityIdentifier = "mainHorizontalStackView"

        [
            thumbnailContainer,
            contentContainer,
        ].forEach(stackView.addArrangedSubview)

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

    lazy var thumbnailTextView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        return imageView
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

        [
            titleLabel,
            subtitleLabel,
            contentBottomSpacerView,
        ].forEach(stackView.addArrangedSubview)

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
            configuration: .init(
                leadingPrimaryAction: .init(
                    image: UIImage(systemName: "arrow.up")!,
                    backgroundColor: UIColor.orange
                ),
                leadingSecondaryAction: .init(
                    image: UIImage(systemName: "arrow.down")!,
                    backgroundColor: UIColor.blue
                ),
                trailingPrimaryAction: .init(
                    image: UIImage(systemName: "arrowshape.turn.up.backward")!,
                    backgroundColor: UIColor.blue
                ),
                trailingSecondaryAction: .init(
                    image: UIImage(systemName: "bookmark")!,
                    backgroundColor: UIColor.green
                )
            )
        )
        view.translatesAutoresizingMaskIntoConstraints = false
        view.trigger = { [weak self] action in
            self?.swipeActionTriggered(action)
        }
        return view
    }()

    // MARK: Private

    private var disposables = Set<AnyCancellable>()

    // MARK: Functions

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        selectionStyle = .none

        contentView.addSubview(swipeActionView)

        [
            thumbnailView,
            thumbnailBottomSpacerView,
        ].forEach(thumbnailContainer.addArrangedSubview)

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

        disposables.removeAll()
        thumbnailView.prepareForReuse()
    }

    func configure(with viewModel: PostListPostViewModel) {
        viewModel.title
            .map { NSAttributedString($0) }
            .wrapInOptional()
            .assign(to: \.attributedText, on: titleLabel)
            .store(in: &disposables)

        viewModel.subtitle
            .wrapInOptional()
            .assign(to: \.attributedText, on: subtitleLabel)
            .store(in: &disposables)

        viewModel.thumbnail
            .map { thumbnailType in
                switch thumbnailType {
                case let .image(image):
                    return .image(image)
                case .imageFailure:
                    return .imageFailure
                case .text:
                    return .text
                }
            }
            .assign(to: \.thumbnailType, on: thumbnailView)
            .store(in: &disposables)
    }

    private func swipeActionTriggered(_ action: SwipeActionView.ActionTrigger) {
        // TODO: handle the action
        print(action)
    }
}
