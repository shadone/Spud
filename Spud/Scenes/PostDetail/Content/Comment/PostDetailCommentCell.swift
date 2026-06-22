//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SpudMarkdownKit
import SpudUIKit
import UIKit

class PostDetailCommentCell: UITableViewCell {
    static let reuseIdentifier = "PostDetailCommentCell"

    // MARK: Public

    var linkTapped: ((URL) -> Void)?
    var linkLongPressed: ((URL) -> Void)?

    /// Builds the context-menu configuration for a long press on a link preview
    /// card, given that card's (tap) URL. Set by the owner, which holds the
    /// services needed to build the menu and preview.
    var linkPreviewContextMenu: ((URL) -> UIContextMenuConfiguration?)?

    /// Commits a link preview card's context-menu preview (e.g. opens the peeked
    /// page) when the user taps the preview.
    var linkPreviewContextMenuCommit: ((UIContextMenuConfiguration, UIContextMenuInteractionCommitAnimating) -> Void)?

    /// Fired when an inline image in the body finishes loading, so the host can
    /// re-measure this row to fit the now-known image height.
    var onBodyImageLoaded: (() -> Void)?

    /// Invoked when the user taps a link inside the comment body markdown.
    var onBodyLinkTapped: ((URL) -> Void)?

    /// Invoked when the user taps an inline image in the comment body markdown.
    var onBodyImageTapped: ((_ url: URL, _ altText: String?, _ sourceRect: CGRect) -> Void)?

    /// Invoked when the user taps a video link in the comment body markdown.
    var onBodyVideoTapped: ((URL) -> Void)?

    /// Invoked when the user taps an audio link in the comment body markdown.
    var onBodyAudioTapped: ((URL) -> Void)?

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

    /// A small persistent dot at the leading edge of the header line marking a
    /// comment as new since the user's last visit. Decorative (VoiceOver gets a
    /// spoken hint instead).
    lazy var newDotView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 7),
            view.heightAnchor.constraint(equalToConstant: 7),
        ])
        view.layer.cornerRadius = 3.5
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
        stackView.addArrangedSubview(bodyView)
        stackView.addArrangedSubview(messageLabel)
        stackView.addArrangedSubview(linkPreviewsStackView)
        stackView.addArrangedSubview(blockedFoldView)

        return stackView
    }()

    /// Holds one `LinkPreviewView` card per previewable link in the comment body,
    /// stacked below the text. Hidden when the comment has no link cards to show.
    lazy var linkPreviewsStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 4
        stackView.isHidden = true
        stackView.accessibilityIdentifier = "linkPreviews"
        return stackView
    }()

    lazy var headerStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.spacing = 0
        stackView.alignment = .center

        let subviews = [
            newDotView,
            authorLabel,
            badgesStackView,
            subtitleLabel,
            spacerView,
            collapsedBadgeLabel,
            collapsedNewBadgeLabel,
        ]
        for view in subviews {
            stackView.addArrangedSubview(view)
        }

        stackView.setCustomSpacing(6, after: newDotView)
        stackView.setCustomSpacing(6, after: authorLabel)
        stackView.setCustomSpacing(6, after: badgesStackView)
        stackView.setCustomSpacing(6, after: collapsedBadgeLabel)

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

    /// Accent "N new" pill shown on a collapsed comment that hides replies new
    /// since the user's last visit, beside the "+N" hidden-count label.
    lazy var collapsedNewBadgeLabel: BadgeLabel = {
        let label = BadgeLabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.layer.cornerRadius = 4
        label.clipsToBounds = true
        label.accessibilityIdentifier = "collapsedNewBadge"
        label.isAccessibilityElement = false
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    /// Rendered comment-body markdown view. Recreated when the text-size or
    /// density preference changes, since `MarkdownBodyView` bakes the context
    /// (fonts, spacing) at init time.
    private(set) lazy var bodyView: MarkdownBodyView = makeBodyView(textScale: 0, density: .comfortable)

    /// Placeholder body for deleted or removed comments (a styled attributed
    /// string with an icon + italic label). Hidden for normal comments that use
    /// `bodyView` instead.
    lazy var messageLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.accessibilityIdentifier = "message"
        return label
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

    // MARK: Private

    /// Maps each rendered `LinkPreviewView` card to its tap URL, so the context
    /// menu delegate can resolve the URL from the interaction's view.
    private var linkPreviewTapURLs: [ObjectIdentifier: URL] = [:]

    /// Text-scale baked into the current `bodyView`. Compared on each configure;
    /// when it changes a new `MarkdownBodyView` is built and swapped into the
    /// stack view so fonts reflect the updated preference.
    private var bodyViewTextScale: CGFloat = 0

    /// Density baked into the current `bodyView`, compared on each configure
    /// alongside `bodyViewTextScale`.
    private var bodyViewDensity: PostDensity = .comfortable

    /// The row's non-fresh resting wash color (clear, or the distinguished /
    /// collapsed tint), captured in `configure` so the fade lands on the right
    /// background instead of always clearing to transparent.
    private var restingTintColor: UIColor = .clear
    /// The fresh-comment tint, captured in `configure` from the resolved accent.
    private var freshTintColor: UIColor = .clear
    private var isFresh = false

    // MARK: Functions

    private func makeBodyView(textScale: CGFloat, density: PostDensity) -> MarkdownBodyView {
        let context = MarkdownContext(kind: .comment, textScale: textScale, density: density)
        let view = MarkdownBodyView(context: context)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.accessibilityIdentifier = "body"
        view.delegate = self
        view.onContentSizeChange = { [weak self] in
            self?.onBodyImageLoaded?()
        }
        return view
    }

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
        linkPreviewContextMenu = nil
        linkPreviewContextMenuCommit = nil
        onBodyImageLoaded = nil
        onBodyLinkTapped = nil
        onBodyImageTapped = nil
        onBodyVideoTapped = nil
        onBodyAudioTapped = nil
        collapseTapped = nil
        revealBlockedTapped = nil
        swipeActionConfiguration = nil
        swipeActionTriggered = nil
        mainHorizontalStackView.alpha = 1
        tintBackingView.layer.removeAnimation(forKey: "freshFade")
        tintBackingView.backgroundColor = .clear
        isFresh = false
        restingTintColor = .clear
        freshTintColor = .clear
        newDotView.isHidden = true
        newDotView.backgroundColor = .clear
        collapsedNewBadgeLabel.attributedText = nil
        collapsedNewBadgeLabel.backgroundColor = .clear
        collapsedNewBadgeLabel.isHidden = true
        // Drop the bodies now so any in-flight inline-image loads are cancelled
        // before the cell is reused for another comment.
        bodyView.setBlocks([])
        bodyView.isHidden = true
        messageLabel.attributedText = nil
        clearBadges()
        clearLinkPreviews()
    }

    private func clearBadges() {
        for view in badgesStackView.arrangedSubviews {
            badgesStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        badgesStackView.isHidden = true
    }

    /// Rebuilds the link-preview stack from the view model. Cards are shown only
    /// when the markdown body itself is shown (so a collapsed / folded / "load
    /// more" / moderation-placeholder row shows none). A tap fires the link's tap
    /// URL through `linkTapped` (not the displayed URL); a long press shows a
    /// system context menu via `UIContextMenuInteraction`.
    private func configureLinkPreviews(_ viewModel: PostDetailCommentViewModel) {
        clearLinkPreviews()

        guard !bodyView.isHidden, !viewModel.linkPreviews.isEmpty else { return }

        linkPreviewsStackView.isHidden = false
        for preview in viewModel.linkPreviews {
            let view = LinkPreviewView()
            view.translatesAutoresizingMaskIntoConstraints = false
            view.url = preview.displayURL
            let tapURL = preview.tapURL
            view.tapped = { [weak self] _ in self?.linkTapped?(tapURL) }
            view.addInteraction(UIContextMenuInteraction(delegate: self))
            linkPreviewTapURLs[ObjectIdentifier(view)] = tapURL
            linkPreviewsStackView.addArrangedSubview(view)
        }
    }

    private func clearLinkPreviews() {
        for view in linkPreviewsStackView.arrangedSubviews {
            linkPreviewsStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        linkPreviewTapURLs.removeAll()
        linkPreviewsStackView.isHidden = true
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

        if viewModel.isMore {
            authorLabel.attributedText = viewModel.moreText
            subtitleLabel.attributedText = nil
            bodyView.setBlocks([])
            bodyView.isHidden = true
            messageLabel.attributedText = nil
            messageLabel.isHidden = true
            clearBadges()
        } else {
            authorLabel.attributedText = viewModel.author
            subtitleLabel.attributedText = viewModel.subtitle

            // Rebuild the body view when the text-scale or density preference
            // changes so fonts are correct; otherwise reuse the existing instance.
            let textScale = viewModel.textSizeAdjustment
            let density = viewModel.commentDensity
            if textScale != bodyViewTextScale || density != bodyViewDensity {
                let oldBodyView = bodyView
                let newBodyView = makeBodyView(textScale: textScale, density: density)
                if let idx = verticalStackView.arrangedSubviews.firstIndex(of: oldBodyView) {
                    verticalStackView.insertArrangedSubview(newBodyView, at: idx)
                    oldBodyView.removeFromSuperview()
                }
                bodyView = newBodyView
                bodyViewTextScale = textScale
                bodyViewDensity = density
            }

            // Normal markdown: use bodyView. Deleted/removed: use messageLabel for
            // the styled placeholder (the blocks array is empty in those cases).
            let hasMarkdownBlocks = !viewModel.bodyBlocks.isEmpty
            if hasMarkdownBlocks {
                // A collapsed comment hides its own body too, Apollo-style.
                let blocks = viewModel.isCollapsed ? [] : viewModel.bodyBlocks
                bodyView.imageLoader = { [imageService] url in
                    for await state in imageService.fetch(url) {
                        if case let .ready(image) = state { return image }
                    }
                    return nil
                }
                bodyView.setBlocks(blocks)
                bodyView.isHidden = viewModel.isCollapsed
                messageLabel.attributedText = nil
                messageLabel.isHidden = true
            } else {
                // Deleted or removed — use the styled placeholder in messageLabel.
                bodyView.setBlocks([])
                bodyView.isHidden = true
                messageLabel.attributedText = viewModel.isCollapsed ? nil : viewModel.body
                messageLabel.isHidden = (messageLabel.attributedText?.length ?? 0) == 0
            }

            clearBadges()
            if !viewModel.badges.isEmpty {
                badgesStackView.isHidden = false
                for badge in viewModel.badges {
                    badgesStackView.addArrangedSubview(makeBadgeView(badge, accent: accent))
                }
            }
        }

        // Blocked-user fold: swap the normal content for the "Blocked user · Show"
        // affordance.
        let folded = viewModel.isBlockedFolded && !viewModel.isMore
        blockedFoldView.isHidden = !folded
        headerStackView.isHidden = folded
        if folded {
            bodyView.isHidden = true
            messageLabel.isHidden = true
            blockedLabel.attributedText = viewModel.blockedFoldedText
            blockedShowLabel.attributedText = viewModel.blockedShowText
        }

        // Link preview cards follow the markdown body's visibility — shown only
        // when `bodyView` is (i.e. not collapsed, folded, "load more", or a
        // moderation placeholder).
        configureLinkPreviews(viewModel)

        collapsedBadgeLabel.attributedText = viewModel.collapsedBadgeText
        collapsedBadgeLabel.isHidden = viewModel.collapsedBadgeText == nil

        if let newCount = viewModel.collapsedNewDescendantCount {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold),
                .foregroundColor: UIColor.white,
            ]
            collapsedNewBadgeLabel.attributedText = NSAttributedString(
                string: "\(newCount) new",
                attributes: attributes
            )
            collapsedNewBadgeLabel.backgroundColor = accent
            collapsedNewBadgeLabel.isHidden = false
        } else {
            collapsedNewBadgeLabel.attributedText = nil
            collapsedNewBadgeLabel.backgroundColor = .clear
            collapsedNewBadgeLabel.isHidden = true
        }

        depthRailsView.railColors = viewModel.depthRailColors

        // Distinguished (official) reads as a teal-washed row; a collapsed row
        // gets a neutral wash. Moderator-removed rows dim.
        if viewModel.isDistinguished {
            restingTintColor = accent.withAlphaComponent(0.10)
        } else if viewModel.isCollapsed {
            restingTintColor = UIColor.label.withAlphaComponent(0.03)
        } else {
            restingTintColor = .clear
        }
        isFresh = viewModel.isNew
        freshTintColor = accent.withAlphaComponent(
            traitCollection.userInterfaceStyle == .dark ? 0.16 : 0.11
        )
        // Resting state by default; the host re-applies the fresh wash in
        // willDisplay (so the one-time fade can run as the row appears).
        tintBackingView.backgroundColor = restingTintColor
        mainHorizontalStackView.alpha = viewModel.isDeemphasized ? 0.66 : 1

        newDotView.isHidden = !viewModel.isNew
        newDotView.backgroundColor = viewModel.isNew ? accent : .clear

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

    /// Applies the fresh-comment wash for this appearance. Returns `true` if it
    /// started the one-time fade (so the host can record that this comment has
    /// animated and not replay it).
    @discardableResult
    func startFreshWashIfNeeded(hasAnimated: Bool) -> Bool {
        let state = FreshWashState.resolve(
            isNew: isFresh,
            hasAnimated: hasAnimated,
            reduceMotion: UIAccessibility.isReduceMotionEnabled
        )
        switch state {
        case .none:
            tintBackingView.layer.removeAnimation(forKey: "freshFade")
            tintBackingView.backgroundColor = restingTintColor
            return false
        case .staticTint:
            tintBackingView.layer.removeAnimation(forKey: "freshFade")
            tintBackingView.backgroundColor = freshTintColor
            return false
        case .fadeFromTint:
            playFreshFade()
            return true
        }
    }

    /// Holds the fresh tint, then fades to the resting background — the design's
    /// spudFreshFade (hold to 38%, fade to 100% over 4.2s, ease-out).
    private func playFreshFade() {
        let resting = restingTintColor.cgColor
        let fresh = freshTintColor.cgColor
        tintBackingView.backgroundColor = restingTintColor // model layer = end state

        let animation = CAKeyframeAnimation(keyPath: "backgroundColor")
        animation.values = [fresh, fresh, resting]
        animation.keyTimes = [0, 0.38, 1.0]
        animation.duration = 4.2
        animation.timingFunctions = [
            CAMediaTimingFunction(name: .linear), // hold: fresh -> fresh
            CAMediaTimingFunction(name: .easeOut), // fade: fresh -> resting
        ]
        tintBackingView.layer.add(animation, forKey: "freshFade")
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

        // Defer to the LinkLabels and the markdown body: if the tap landed on an
        // actual link range, a media tile, or an interactive control (the body
        // hit-tests its own contents), let the view handle it and do not collapse.
        let point = recognizer.location(in: contentView)
        if labelHasLink(authorLabel, at: point) || labelHasLink(bodyView, at: point) {
            return
        }

        // A tap on a link-preview card is handled by the card's own button; don't
        // also collapse the thread.
        if !linkPreviewsStackView.isHidden {
            let pointInStack = contentView.convert(point, to: linkPreviewsStackView)
            if linkPreviewsStackView.bounds.contains(pointInStack) {
                return
            }
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
/// by `LinkLabel` (author) and `MarkdownBodyView` (markdown body).
protocol BodyLinkHitTesting: UIView {
    func hasLink(at point: CGPoint) -> Bool
}

extension LinkLabel: BodyLinkHitTesting { }

/// Reports whether a point lands on an actual tappable link, media tile, or
/// control inside the markdown body, so the collapse-tap defers to those and
/// still collapses on plain-text taps.
extension MarkdownBodyView: BodyLinkHitTesting {
    public func hasLink(at point: CGPoint) -> Bool {
        handlesTap(at: point)
    }
}

// MARK: - MarkdownBodyDelegate

extension PostDetailCommentCell: MarkdownBodyDelegate {
    func markdownBody(didTapLink url: URL) {
        onBodyLinkTapped?(url)
    }

    func markdownBody(didTapImage url: URL, altText: String?, sourceRect: CGRect) {
        onBodyImageTapped?(url, altText, sourceRect)
    }

    func markdownBody(didTapVideo url: URL) {
        onBodyVideoTapped?(url)
    }

    func markdownBody(didTapAudio url: URL) {
        onBodyAudioTapped?(url)
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

// MARK: - UIContextMenuInteractionDelegate

extension PostDetailCommentCell: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation _: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard
            let view = interaction.view,
            let url = linkPreviewTapURLs[ObjectIdentifier(view)]
        else {
            return nil
        }
        return linkPreviewContextMenu?(url)
    }

    func contextMenuInteraction(
        _: UIContextMenuInteraction,
        willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
        animator: UIContextMenuInteractionCommitAnimating
    ) {
        linkPreviewContextMenuCommit?(configuration, animator)
    }
}
