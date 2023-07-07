//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import UIKit

class PostDetailHeaderCell: UITableViewCell {
    static let reuseIdentifier = "PostDetailHeaderCell"

    // MARK: UI Properties

    lazy var mainVerticalStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .leading
        stackView.spacing = 8
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

    // MARK: Functions

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        selectionStyle = .none

        contentView.addSubview(mainVerticalStackView)

        [
            titleLabel,
            bodyLabel,
            linkPreviewView,
            attributionLabel,
            subtitleHorizontalStackView,
        ].forEach(mainVerticalStackView.addArrangedSubview)

        let linkPreviewWidthConstraint = linkPreviewView.widthAnchor.constraint(equalToConstant: 200)
        linkPreviewWidthConstraint.priority = .defaultLow
        let linkPreviewTrailingConstraint = linkPreviewView.trailingAnchor.constraint(lessThanOrEqualTo: mainVerticalStackView.trailingAnchor, constant: -8)

        NSLayoutConstraint.activate([
            mainVerticalStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            mainVerticalStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            mainVerticalStackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            mainVerticalStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),

            linkPreviewWidthConstraint,
            linkPreviewTrailingConstraint,
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
    }

    private func linkPreviewTapped(_ url: URL) {
        UIApplication.shared.open(url)
    }
}
