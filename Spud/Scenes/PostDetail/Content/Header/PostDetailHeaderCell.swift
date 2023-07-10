//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import UIKit

class PostDetailHeaderCell: UITableViewCellBase {
    static let reuseIdentifier = "PostDetailHeaderCell"

    // MARK: UI Properties

    lazy var mainVerticalStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 8
        stackView.accessibilityIdentifier = "mainVerticalStackView"

        [
            postImageContainer,
            postContentVerticalStackView,
        ].forEach(stackView.addArrangedSubview)

        NSLayoutConstraint.activate([
            postImageContainer.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            postContentVerticalStackView.widthAnchor.constraint(
                equalTo: stackView.widthAnchor, constant: -16 * 2),
        ])

        return stackView
    }()

    lazy var postImageContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .tertiarySystemGroupedBackground
        view.accessibilityIdentifier = "postImageContainer"
        return view
    }()

    lazy var postImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.accessibilityIdentifier = "postImageView"
        return imageView
    }()

    lazy var postContentVerticalStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .leading
        stackView.spacing = 8
        stackView.accessibilityIdentifier = "postContentVerticalStackView"

        [
            postImageContainer,
            titleLabel,
            bodyLabel,
            linkPreviewView,
            attributionLabel,
            subtitleHorizontalStackView,
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

    lazy var bodyLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.accessibilityIdentifier = "body"
        return label
    }()

    lazy var linkPreviewView: LinkPreviewView = {
        let view = LinkPreviewView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.tapped = { [weak self] url in
            self?.linkPreviewTapped(url)
        }
        return view
    }()

    lazy var attributionLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.accessibilityIdentifier = "attribution"
        return label
    }()

    lazy var subtitleHorizontalStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.spacing = 2

        let spacerView = UIView()
        spacerView.backgroundColor = .clear
        spacerView.setContentHuggingPriority(.defaultLow, for: .horizontal)

        stackView.addArrangedSubview(subtitleScoreLabel)
        stackView.addArrangedSubview(subtitleCommentLabel)
        stackView.addArrangedSubview(subtitleAgeLabel)
        stackView.addArrangedSubview(spacerView)

        return stackView
    }()

    lazy var subtitleScoreLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        return label
    }()

    lazy var subtitleCommentLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        return label
    }()

    lazy var subtitleAgeLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        return label
    }()

    // MARK: Private

    private var disposables = Set<AnyCancellable>()

    private var postImageContainerHeightConstraint: NSLayoutConstraint!

    // MARK: Functions

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        selectionStyle = .none

        postImageContainer.addSubview(postImageView)
        contentView.addSubview(mainVerticalStackView)

        let postImageContainerHeightConstraint = postImageContainer.heightAnchor.constraint(equalToConstant: 0)
        self.postImageContainerHeightConstraint = postImageContainerHeightConstraint

        let linkPreviewWidthConstraint = linkPreviewView.widthAnchor.constraint(equalToConstant: 200)
        linkPreviewWidthConstraint.priority = .defaultLow
        let linkPreviewTrailingConstraint = linkPreviewView.trailingAnchor.constraint(lessThanOrEqualTo: mainVerticalStackView.trailingAnchor, constant: -8)

        NSLayoutConstraint.activate([
            mainVerticalStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            mainVerticalStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            mainVerticalStackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            mainVerticalStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            linkPreviewWidthConstraint,
            linkPreviewTrailingConstraint,

            postImageView.leadingAnchor.constraint(equalTo: postImageContainer.leadingAnchor),
            postImageView.trailingAnchor.constraint(equalTo: postImageContainer.trailingAnchor),
            postImageView.topAnchor.constraint(equalTo: postImageContainer.topAnchor),
            postImageView.bottomAnchor.constraint(equalTo: postImageContainer.bottomAnchor),

            postImageContainerHeightConstraint,
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        disposables.removeAll()

        linkPreviewView.isHidden = true
        linkPreviewView.prepareForReuse()

        postImageContainer.isHidden = true
    }

    func configure(with viewModel: PostDetailHeaderViewModel) {
        viewModel.title
            .map { NSAttributedString($0) }
            .wrapInOptional()
            .assign(to: \.attributedText, on: titleLabel)
            .store(in: &disposables)

        viewModel.body
            .map { NSAttributedString($0) }
            .wrapInOptional()
            .assign(to: \.attributedText, on: bodyLabel)
            .store(in: &disposables)

        viewModel.attribution
            .wrapInOptional()
            .assign(to: \.attributedText, on: attributionLabel)
            .store(in: &disposables)

        viewModel.subtitleScore
            .wrapInOptional()
            .assign(to: \.attributedText, on: subtitleScoreLabel)
            .store(in: &disposables)

        viewModel.subtitleComments
            .wrapInOptional()
            .assign(to: \.attributedText, on: subtitleCommentLabel)
            .store(in: &disposables)

        viewModel.subtitleAge
            .wrapInOptional()
            .assign(to: \.attributedText, on: subtitleAgeLabel)
            .store(in: &disposables)

        viewModel.linkPreviewThumbnail
            .sink(receiveValue: { [weak self] thumbnail in
                switch thumbnail {
                case let .image(image):
                    self?.linkPreviewView.thumbnailImage = image
                    self?.linkPreviewView.isHidden = false
                case .imageFailure:
                    self?.linkPreviewView.isHidden = false
                case .none:
                    self?.linkPreviewView.isHidden = true
                }
            })
            .store(in: &disposables)

        viewModel.url
            .sink(receiveValue: { [weak self] url in
                self?.linkPreviewView.url = url
                self?.linkPreviewView.isHidden = false
            })
            .store(in: &disposables)

        viewModel.image
            .sink { [weak self] imageLoadingState in
                switch imageLoadingState {
                case .loading:
                    // TODO: display loading indicator
                    break

                case let .ready(image):
                    self?.setImage(image)

                case .failure:
                    // TODO: Image loading failed. Display retry button to try to load the image again.
                    break
                }
            }
            .store(in: &disposables)
    }

    private func linkPreviewTapped(_ url: URL) {
        UIApplication.shared.open(url)
    }

    private func setImage(_ image: UIImage) {
        postImageView.image = image
        postImageContainer.isHidden = false

        assert(tableView != nil)
        let cellWidth = tableView?.bounds.width ?? 100
        postImageContainerHeightConstraint.constant = image.fittingHeight(for: cellWidth)

        if !isBeingConfigured {
            // Tell UITableView we want to change our cell height.
            tableView?.beginUpdates()
            tableView?.endUpdates()
        }
    }
}
