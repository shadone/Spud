//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

class PostDetailCommentCell: UITableViewCell {
    static let reuseIdentifier = "PostDetailCommentCell"

    // MARK: Public

    var linkTapped: ((URL) -> Void)?

    /// Fired when the user taps the comment body/header (but not a link or a
    /// swipe action) to collapse or expand its thread.
    var collapseTapped: (() -> Void)?

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
        stackView.spacing = 0
        stackView.alignment = .fill
        stackView.accessibilityIdentifier = "mainHorizontalStackView"

        let subviews = [
            depthRailsView,
            verticalStackView,
        ]
        for view in subviews {
            stackView.addArrangedSubview(view)
        }

        stackView.setCustomSpacing(8, after: depthRailsView)

        return stackView
    }()

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

        let subviews = [
            authorLabel,
            subtitleLabel,
            spacerView,
            collapsedBadgeLabel,
        ]
        for view in subviews {
            stackView.addArrangedSubview(view)
        }

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

    /// Shows the "+N" collapsed-descendant badge when the comment is collapsed.
    lazy var collapsedBadgeLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.backgroundColor = .clear
        label.accessibilityIdentifier = "collapsedBadge"
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
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

    /// Draws one thin colored vertical rail per ancestor depth on the leading
    /// edge, so thread depth is visually scannable.
    lazy var depthRailsView: DepthRailsView = {
        let view = DepthRailsView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentCompressionResistancePriority(.required, for: .horizontal)
        return view
    }()

    lazy var swipeActionView: SwipeActionView = {
        let view = SwipeActionView(
            contentView: mainHorizontalStackView,
            margin: UIEdgeInsets(top: 8, left: 4, bottom: -8, right: -8),
            configuration: nil
        )
        view.translatesAutoresizingMaskIntoConstraints = false
        view.trigger = { [weak self] action in
            self?.swipeActionTriggered?(action)
        }
        return view
    }()

    private lazy var collapseTapGestureRecognizer: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer(
            target: self,
            action: #selector(handleCollapseTap(_:))
        )
        recognizer.delegate = self
        return recognizer
    }()

    // MARK: Functions

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        selectionStyle = .none

        contentView.addSubview(swipeActionView)

        NSLayoutConstraint.activate([
            swipeActionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            swipeActionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            swipeActionView.topAnchor.constraint(equalTo: contentView.topAnchor),
            swipeActionView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        contentView.addGestureRecognizer(collapseTapGestureRecognizer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        linkTapped = nil
        collapseTapped = nil
        swipeActionConfiguration = nil
        swipeActionTriggered = nil
    }

    func configure(with viewModel: PostDetailCommentViewModel) {
        if viewModel.isMore {
            authorLabel.attributedText = viewModel.moreText
            subtitleLabel.attributedText = nil
            messageLabel.attributedText = nil
        } else {
            authorLabel.attributedText = viewModel.author
            subtitleLabel.attributedText = viewModel.subtitle
            // A collapsed comment hides its own body too, Apollo-style: only the
            // header line (author + score + "+N") remains.
            messageLabel.attributedText = viewModel.isCollapsed ? nil : viewModel.body
        }
        messageLabel.isHidden = (messageLabel.attributedText?.length ?? 0) == 0

        collapsedBadgeLabel.attributedText = viewModel.collapsedBadgeText
        collapsedBadgeLabel.isHidden = viewModel.collapsedBadgeText == nil

        depthRailsView.railColors = viewModel.depthRailColors

        // A "load more" placeholder is not itself collapsible.
        collapseTapGestureRecognizer.isEnabled = !viewModel.isMore

        // Accessibility: the subtitle element carries the comment metadata
        // (score, age, depth, collapsed/moderation state) in a spoken form —
        // the visible run is SF Symbols + numbers VoiceOver cannot pronounce.
        // The author (a LinkLabel) and the body are read as their own elements.
        subtitleLabel.accessibilityLabel = viewModel.subtitleAccessibilityLabel
        // The depth rails are decorative; hide them from VoiceOver.
        depthRailsView.isAccessibilityElement = false
        // Surface the collapse/expand affordance on the cell so VoiceOver users
        // can act on it without hunting for the tap target.
        accessibilityHint = viewModel.collapseAccessibilityHint
        if viewModel.isMore {
            accessibilityTraits = .button
        } else {
            accessibilityTraits = .none
        }
    }

    // MARK: Collapse tap

    @objc
    private func handleCollapseTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }

        // Defer to the LinkLabels: if the tap landed on an actual link range,
        // let the label handle it and do not collapse.
        let point = recognizer.location(in: contentView)
        if labelHasLink(authorLabel, at: point) || labelHasLink(messageLabel, at: point) {
            return
        }

        collapseTapped?()
    }

    private func labelHasLink(_ label: LinkLabel, at point: CGPoint) -> Bool {
        guard !label.isHidden, label.window != nil else { return false }
        let pointInLabel = contentView.convert(point, to: label)
        guard label.bounds.contains(pointInLabel) else { return false }
        return label.hasLink(at: pointInLabel)
    }
}

// MARK: - UIGestureRecognizerDelegate

extension PostDetailCommentCell {
    override func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Coexist with the LinkLabel tap recognizers (we filter link hits in
        // the handler) and with the swipe pan recognizer.
        true
    }
}
