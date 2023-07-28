//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import UIKit

class PostDetailHeaderCell: UITableViewCellBase {
    static let reuseIdentifier = "PostDetailHeaderCell"

    // MARK: Public

    var linkTapped: ((URL) -> Void)?

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

    lazy var bodyLabel: LinkLabel = {
        let label = LinkLabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.accessibilityIdentifier = "body"
        label.tapped = { [weak self] url in
            self?.linkTapped?(url)
        }
        return label
    }()

    lazy var linkPreviewView: LinkPreviewView = {
        let view = LinkPreviewView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.tapped = { [weak self] url in
            self?.linkTapped?(url)
        }
        return view
    }()

    lazy var attributionLabel: LinkLabel = {
        let label = LinkLabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.accessibilityIdentifier = "attribution"
        label.linkTextAttributes = [:]
        label.highlightedLinkTextAttributes = [:]
        label.tapped = { [weak self] url in
            self?.linkTapped?(url)
        }
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

        prepareForReuse()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        disposables.removeAll()
        linkTapped = nil

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
            .sink(receiveValue: { [weak self] tuple in
                self?.configureLinkPreview(tuple)
            })
            .store(in: &disposables)

        viewModel.image
            .sink { [weak self] imageLoadingState in
                switch imageLoadingState {
                case let .loading(thumbnailImage):
                    if let thumbnailImage {
                        // TODO: display loading indicator
                        self?.setImage(thumbnailImage)
                    }

                case let .ready(image):
                    self?.setImage(image)

                case .failure:
                    // TODO: Image loading failed. Display retry button to try to load the image again.
                    break
                }
            }
            .store(in: &disposables)
    }

    private func configureLinkPreview(_ tuple: (URL, ImageLoadingState)?) {
        guard
            let url = tuple?.0,
            let thumbnailType = tuple?.1
        else {
            linkPreviewView.isHidden = true
            return
        }

        linkPreviewView.url = url
        linkPreviewView.isHidden = false

        switch thumbnailType {
        case .loading:
            // noop. We just show the link preview which was already done above.
            break

        case let .ready(image):
            linkPreviewView.thumbnailImage = image

        case .failure:
            // TODO: display broken image icon
            break
        }

        if !isBeingConfigured {
            // Tell UITableView we want to change our cell height.
            tableView?.beginUpdates()
            tableView?.endUpdates()
        }
    }

    private func setImage(_ image: UIImage) {
        postImageView.image = image
        postImageContainer.isHidden = false

        assert(tableView != nil)
        let cellWidth = tableView?.bounds.width ?? 100
        let maxImageHeight = (tableView?.bounds.height ?? 800) * 0.6
        let imageFittingHeight = image.fittingHeight(for: cellWidth)
        let imageHeight = min(imageFittingHeight, maxImageHeight)

        postImageContainerHeightConstraint.constant = imageHeight

        if !isBeingConfigured {
            // Tell UITableView we want to change our cell height.
            tableView?.beginUpdates()
            tableView?.endUpdates()
        }
    }
}
