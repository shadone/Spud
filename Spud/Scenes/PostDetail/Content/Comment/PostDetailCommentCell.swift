//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import UIKit

class PostDetailCommentCell: UITableViewCell {
    static let reuseIdentifier = "PostDetailCommentCell"

    // MARK: Public

    var linkTapped: ((URL) -> Void)?
    var linkLongPressed: ((URL) -> Void)?

    /// Fired when an inline image in the body finishes loading, so the host can
    /// re-measure this row to fit the now-known image height.
    var onBodyImageLoaded: (() -> Void)?

    /// Fired when the user taps the comment body/header (but not a link or a
    /// swipe action) to collapse or expand its thread.
    var collapseTapped: (() -> Void)?

    /// Fired when the user taps "Show" on a folded blocked-user comment.
    var revealBlockedTapped: (() -> Void)?

    var swipeActionConfiguration: SwipeActionView.Configuration? {
        get { swipeActionView.configuration }
        set { swipeActionView.configuration = newValue }
    }

    var swipeActionTriggered: ((SwipeActionView.ActionTrigger) -> Void)?

    // MARK: UI Properties

    /// A faint full-bleed tint behind the row content — teal for a distinguished
    /// (official) comment, a neutral wash for a collapsed one.
    lazy var tintBackingView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }()

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
        stackView.addArrangedSubview(blockedFoldView)

        return stackView
    }()

    lazy var headerStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.spacing = 0
        stackView.alignment = .center

        let subviews = [
            authorLabel,
            badgesStackView,
            subtitleLabel,
            spacerView,
            collapsedBadgeLabel,
        ]
        for view in subviews {
            stackView.addArrangedSubview(view)
        }

        stackView.setCustomSpacing(6, after: authorLabel)
        stackView.setCustomSpacing(6, after: badgesStackView)

        return stackView
    }()

    /// Expands to push the metadata left and the saved/collapsed badges right.
    private lazy var spacerView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return view
    }()

    lazy var authorLabel: LinkLabel = {
        let label = LinkLabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.backgroundColor = .clear
        label.accessibilityIdentifier = "author"
        label.linkTextAttributes = [:]
        label.highlightedLinkTextAttributes = [:]
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.tapped = { [weak self] url in
            self?.linkTapped?(url)
        }
        label.longPressed = { [weak self] url in
            self?.linkLongPressed?(url)
        }
        return label
    }()

    /// Author role/status pills (OP / MOD / ADMIN / BOT / BANNED / SUSPENDED),
    /// rebuilt on each `configure`.
    lazy var badgesStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.spacing = 4
        stackView.alignment = .center
        stackView.accessibilityIdentifier = "badges"
        stackView.setContentHuggingPriority(.required, for: .horizontal)
        stackView.setContentCompressionResistancePriority(.required, for: .horizontal)
        return stackView
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

    lazy var messageLabel: BodyTextView = {
        let view = BodyTextView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.accessibilityIdentifier = "message"
        view.tapped = { [weak self] url in
            self?.linkTapped?(url)
        }
        view.onContentSizeChange = { [weak self] in
            self?.onBodyImageLoaded?()
        }
        return view
    }()

    /// Folded presentation for a blocked user's comment: "Blocked user … Show".
    /// Hidden unless the row is folded.
    lazy var blockedFoldView: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.isHidden = true
        container.accessibilityIdentifier = "blockedFold"

        let stack = UIStackView(arrangedSubviews: [blockedIconView, blockedLabel, blockedShowLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        blockedLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleRevealBlockedTap))
        container.addGestureRecognizer(tap)
        return container
    }()

    private lazy var blockedIconView: UIImageView = {
        let view = UIImageView(image: UIImage(systemName: "eye.slash"))
        view.tintColor = .tertiaryLabel
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.contentMode = .scaleAspectFit
        return view
    }()

    private lazy var blockedLabel: UILabel = {
        let label = UILabel()
        label.accessibilityIdentifier = "blockedLabel"
        return label
    }()

    private lazy var blockedShowLabel: UILabel = {
        let label = UILabel()
        label.accessibilityIdentifier = "blockedShow"
        label.setContentHuggingPriority(.required, for: .horizontal)
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

        contentView.addSubview(tintBackingView)
        contentView.addSubview(swipeActionView)

        NSLayoutConstraint.activate([
            tintBackingView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tintBackingView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            tintBackingView.topAnchor.constraint(equalTo: contentView.topAnchor),
            tintBackingView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

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
        linkLongPressed = nil
        onBodyImageLoaded = nil
        collapseTapped = nil
        revealBlockedTapped = nil
        swipeActionConfiguration = nil
        swipeActionTriggered = nil
        mainHorizontalStackView.alpha = 1
        tintBackingView.backgroundColor = .clear
        // Drop the body now so any in-flight inline-image loads are cancelled
        // before the cell is reused for another comment.
        messageLabel.attributedText = nil
        clearBadges()
    }

    private func clearBadges() {
        for view in badgesStackView.arrangedSubviews {
            badgesStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        badgesStackView.isHidden = true
    }

    /// A `UILabel` with small horizontal padding, used for the rounded badge pills.
    final class BadgeLabel: UILabel {
        private let insets = UIEdgeInsets(top: 1, left: 5, bottom: 1, right: 5)

        override func drawText(in rect: CGRect) {
            super.drawText(in: rect.inset(by: insets))
        }

        override var intrinsicContentSize: CGSize {
            let size = super.intrinsicContentSize
            return CGSize(
                width: size.width + insets.left + insets.right,
                height: size.height + insets.top + insets.bottom
            )
        }
    }

    /// Builds one rounded pill for a badge, tinting OP with the resolved accent.
    private func makeBadgeView(_ badge: CommentBadge, accent: UIColor) -> UIView {
        let label = BadgeLabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.layer.cornerRadius = 4
        label.clipsToBounds = true
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)

        let color = badge.usesAccent ? accent : badge.color
        let textColor: UIColor = badge.solid ? .white : color
        label.backgroundColor = badge.solid ? color : color.withAlphaComponent(0.16)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: textColor,
        ]
        let text = NSMutableAttributedString()
        if let symbolName = badge.symbolName, let image = UIImage(systemName: symbolName) {
            text.append(NSAttributedString.symbol(from: image, attributes: attributes))
            text.append(NSAttributedString(string: " ", attributes: attributes))
        }
        text.append(NSAttributedString(string: badge.text, attributes: attributes))
        label.attributedText = text
        return label
    }

    func configure(with viewModel: PostDetailCommentViewModel, imageService: ImageServiceType) {
        let accent = tintColor ?? .systemTeal

        // Set before the body so inline images can begin loading immediately.
        messageLabel.imageService = imageService

        if viewModel.isMore {
            authorLabel.attributedText = viewModel.moreText
            subtitleLabel.attributedText = nil
            messageLabel.attributedText = nil
            clearBadges()
        } else {
            authorLabel.attributedText = viewModel.author
            subtitleLabel.attributedText = viewModel.subtitle
            // A collapsed comment hides its own body too, Apollo-style: only the
            // header line (author + score + "+N") remains.
            messageLabel.attributedText = viewModel.isCollapsed ? nil : viewModel.body

            clearBadges()
            if !viewModel.badges.isEmpty {
                badgesStackView.isHidden = false
                for badge in viewModel.badges {
                    badgesStackView.addArrangedSubview(makeBadgeView(badge, accent: accent))
                }
            }
        }
        messageLabel.isHidden = (messageLabel.attributedText?.length ?? 0) == 0

        // Blocked-user fold: swap the normal content for the "Blocked user · Show"
        // affordance.
        let folded = viewModel.isBlockedFolded && !viewModel.isMore
        blockedFoldView.isHidden = !folded
        headerStackView.isHidden = folded
        if folded {
            messageLabel.isHidden = true
            blockedLabel.attributedText = viewModel.blockedFoldedText
            blockedShowLabel.attributedText = viewModel.blockedShowText
        }

        collapsedBadgeLabel.attributedText = viewModel.collapsedBadgeText
        collapsedBadgeLabel.isHidden = viewModel.collapsedBadgeText == nil

        depthRailsView.railColors = viewModel.depthRailColors

        // Distinguished (official) reads as a teal-washed row; a collapsed row
        // gets a neutral wash. Moderator-removed rows dim.
        if viewModel.isDistinguished {
            tintBackingView.backgroundColor = accent.withAlphaComponent(0.10)
        } else if viewModel.isCollapsed {
            tintBackingView.backgroundColor = UIColor.label.withAlphaComponent(0.03)
        } else {
            tintBackingView.backgroundColor = .clear
        }
        mainHorizontalStackView.alpha = viewModel.isDeemphasized ? 0.66 : 1

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

    // MARK: Taps

    @objc
    private func handleRevealBlockedTap() {
        revealBlockedTapped?()
    }

    @objc
    private func handleCollapseTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }

        // A folded blocked row handles its own "Show" tap.
        if !blockedFoldView.isHidden {
            return
        }

        // Defer to the LinkLabels: if the tap landed on an actual link range,
        // let the label handle it and do not collapse.
        let point = recognizer.location(in: contentView)
        if labelHasLink(authorLabel, at: point) || labelHasLink(messageLabel, at: point) {
            return
        }

        collapseTapped?()
    }

    private func labelHasLink(_ label: BodyLinkHitTesting, at point: CGPoint) -> Bool {
        guard !label.isHidden, label.window != nil else { return false }
        let pointInLabel = contentView.convert(point, to: label)
        guard label.bounds.contains(pointInLabel) else { return false }
        return label.hasLink(at: pointInLabel)
    }
}

/// A view that can report whether a point lands on a tappable link or inline
/// image, so the comment collapse-tap can defer to link/image taps. Implemented
/// by both `LinkLabel` (author) and `BodyTextView` (body).
protocol BodyLinkHitTesting: UIView {
    func hasLink(at point: CGPoint) -> Bool
}

extension LinkLabel: BodyLinkHitTesting { }
extension BodyTextView: BodyLinkHitTesting { }

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
