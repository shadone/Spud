//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import UIKit

class PostDetailCommentCell: UITableViewCell {
    static let reuseIdentifier = "PostDetailCommentCell"

    // MARK: Public

    var linkTapped: ((URL) -> Void)?

    // MARK: UI Properties

    lazy var verticalStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 4

        stackView.addArrangedSubview(headerStackView)
        stackView.addArrangedSubview(messageLabel)

        return stackView
    }()

    lazy var headerStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.spacing = 0

        let spacerView = UIView()
        spacerView.backgroundColor = .clear
        spacerView.setContentHuggingPriority(.defaultLow, for: .horizontal)

        [
            authorLabel,
            subtitleLabel,
            spacerView,
        ].forEach(stackView.addArrangedSubview)

        stackView.setCustomSpacing(4, after: authorLabel)

        return stackView
    }()

    lazy var authorLabel: LinkLabel = {
        let label = LinkLabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.backgroundColor = .clear
        label.accessibilityIdentifier = "author"
        label.linkTextAttributes = [:]
        label.highlightedLinkTextAttributes = [:]
        label.tapped = { [weak self] url in
            self?.linkTapped?(url)
        }
        return label
    }()

    lazy var subtitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.backgroundColor = .clear
        label.accessibilityIdentifier = "subtitle"
        return label
    }()

    lazy var messageLabel: LinkLabel = {
        let label = LinkLabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.accessibilityIdentifier = "message"
        label.tapped = { [weak self] url in
            self?.linkTapped?(url)
        }
        return label
    }()

    var indentationRibbonViewLeadingConstaint: NSLayoutConstraint!
    var indentationRibbonWidthConstraint: NSLayoutConstraint!

    lazy var indentationRibbonView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // MARK: Private

    private var disposables = Set<AnyCancellable>()

    var ribbonColor: UIColor = .lightGray {
        didSet {
            ribbonColorChanged()
        }
    }

    // MARK: Functions

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        selectionStyle = .none

        contentView.addSubview(indentationRibbonView)
        contentView.addSubview(verticalStackView)

        let indentationRibbonViewLeadingConstaint = indentationRibbonView.leadingAnchor
            .constraint(equalTo: contentView.leadingAnchor)
        self.indentationRibbonViewLeadingConstaint = indentationRibbonViewLeadingConstaint

        let indentationRibbonWidthConstraint = indentationRibbonView.widthAnchor
            .constraint(equalToConstant: 2)
        self.indentationRibbonWidthConstraint = indentationRibbonWidthConstraint

        NSLayoutConstraint.activate([
            indentationRibbonViewLeadingConstaint,
            indentationRibbonView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            indentationRibbonView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            indentationRibbonWidthConstraint,

            verticalStackView.leadingAnchor.constraint(equalTo: indentationRibbonView.trailingAnchor, constant: 8),
            verticalStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            verticalStackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            verticalStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),

            messageLabel.leadingAnchor.constraint(equalTo: verticalStackView.leadingAnchor),
            messageLabel.trailingAnchor.constraint(equalTo: verticalStackView.trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        disposables.removeAll()
        linkTapped = nil
    }

    func configure(with viewModel: PostDetailCommentViewModel) {
        viewModel.author
            .wrapInOptional()
            .assign(to: \.attributedText, on: authorLabel)
            .store(in: &disposables)

        viewModel.subtitle
            .wrapInOptional()
            .assign(to: \.attributedText, on: subtitleLabel)
            .store(in: &disposables)

        viewModel.body
            .wrapInOptional()
            .assign(to: \.attributedText, on: messageLabel)
            .store(in: &disposables)

        viewModel.indentationRibbonLeadingMargin
            .assign(to: \.constant, on: indentationRibbonViewLeadingConstaint)
            .store(in: &disposables)

        viewModel.indentationRibbonWidth
            .assign(to: \.constant, on: indentationRibbonWidthConstraint)
            .store(in: &disposables)

        viewModel.indentationRibbonColor
            .sink(receiveValue: { [weak self] color in
                self?.ribbonColor = color
            })
            .store(in: &disposables)
    }

    private func ribbonColorChanged() {
        indentationRibbonView.backgroundColor = ribbonColor
    }
}
