//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudDataKit
import SpudMarkdownKit
import SpudUIKit
import UIKit

/// Apollo-style community header: banner image, overlapping circular icon,
/// title, "!name@instance" handle, subscriber/post counts, a markdown
/// description, and a prominent state-aware Subscribe/Unsubscribe button.
///
/// Layout-only; the owning view controller drives it via `configure(...)`,
/// loads images, and wires the button / description-link callbacks.
final class CommunityHeaderView: UIView {
    /// Fired when the Subscribe/Unsubscribe button is tapped.
    var subscribeTapped: (() -> Void)?
    /// Fired when a link inside the markdown description is tapped (raw renderer
    /// URL; the host resolves `spud-markdown://` mentions).
    var onBodyLinkTapped: ((URL) -> Void)?
    /// Fired when a loaded inline description image is tapped (zoom).
    var onBodyImageTapped: ((_ url: URL, _ altText: String?, _ sourceRect: CGRect) -> Void)?
    /// Fired when an inline description video tile is tapped.
    var onBodyVideoTapped: ((URL) -> Void)?
    /// Fired when an inline description audio tile is tapped.
    var onBodyAudioTapped: ((URL) -> Void)?
    /// Fired when the "!name@instance" handle label is tapped.
    var onInstanceTapped: (() -> Void)?

    /// The image loader used for inline description images. Set by the owning
    /// view controller before `configure(...)`.
    var imageService: ImageServiceType?

    /// Fired whenever the description's rendered height changes — when the async
    /// markdown parse lands its blocks, when a spoiler toggles, or when an inline
    /// description image finishes loading — so the host can re-measure its
    /// scrolling table header (which does not self-size).
    var onDescriptionHeightChanged: (() -> Void)?

    /// Bumped on each `configureDescription` so a slower off-main parse from an
    /// earlier call can't land its blocks after a newer one.
    private var descriptionToken = 0

    private let bannerHeight: CGFloat = 120
    private let iconSize: CGFloat = 64

    // MARK: Subviews

    private lazy var bannerImageView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.backgroundColor = .secondarySystemBackground
        return view
    }()

    private lazy var iconImageView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.layer.cornerRadius = iconSize / 2
        view.layer.borderWidth = 3
        view.layer.borderColor = UIColor.systemBackground.cgColor
        view.backgroundColor = .tertiarySystemBackground
        view.image = UIImage(systemName: "person.3.fill")
        view.tintColor = .secondaryLabel
        return view
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .title2)
        label.adjustsFontForContentSizeCategory = true
        label.font = UIFont.boldSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .title2).pointSize)
        label.numberOfLines = 2
        return label
    }()

    private lazy var handleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        return label
    }()

    private lazy var statsLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        return label
    }()

    /// Network-activity line (weekly / monthly active users) from the Explorer
    /// directory. Hidden when the community isn't in the directory.
    private lazy var vitalityLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        label.isHidden = true
        return label
    }()

    /// Stacks the subscriber/post counts above the vitality line so the latter
    /// collapses cleanly when there's no Explorer data.
    private lazy var metaStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [statsLabel, vitalityLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 3
        stack.alignment = .leading
        return stack
    }()

    private lazy var descriptionView: MarkdownBodyView = {
        let context = MarkdownContext(kind: .post, textScale: 0, density: .comfortable)
        let view = MarkdownBodyView(context: context)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.accessibilityIdentifier = "description"
        view.delegate = self
        view.onContentSizeChange = { [weak self] in
            self?.onDescriptionHeightChanged?()
        }
        return view
    }()

    private lazy var subscribeButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .medium
        config.buttonSize = .medium
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(subscribeButtonTapped), for: .touchUpInside)
        return button
    }()

    /// Pill shown in the title area when the community is marked NSFW.
    private lazy var nsfwBadge: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = NSLocalizedString("NSFW", comment: "NSFW badge on community header")
        label.font = UIFont.systemFont(ofSize: 9, weight: .heavy)
        label.textColor = .white
        label.backgroundColor = .systemRed
        label.textAlignment = .center
        label.layer.cornerRadius = 4
        label.layer.masksToBounds = true
        label.isHidden = true
        return label
    }()

    /// Pill shown in the title area when the community is classified "meta" for
    /// its own home instance (e.g. an announcements / site community) via
    /// `MetaCommunityClassifier`. Neutral-tinted (unlike the alarming NSFW red)
    /// since this is informational, not a content warning.
    private lazy var metaBadge: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = NSLocalizedString("META", comment: "Meta community badge on community header")
        label.font = UIFont.systemFont(ofSize: 9, weight: .heavy)
        label.textColor = .white
        label.backgroundColor = .secondaryLabel
        label.textAlignment = .center
        label.layer.cornerRadius = 4
        label.layer.masksToBounds = true
        label.isHidden = true
        label.accessibilityLabel = NSLocalizedString("Instance community", comment: "Meta community badge")
        return label
    }()

    /// Hosts the NSFW + meta pills side by side after the title. Each pill is an
    /// independently-hideable arranged subview: a `UIStackView` collapses a
    /// hidden arranged subview's width AND its spacing entirely (unlike a plain
    /// subview, which keeps reserving its constrained frame once hidden), so
    /// every visibility combination — neither, either alone, or both — lays out
    /// correctly without a fragile per-combination constraint chain.
    private lazy var badgeStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [nsfwBadge, metaBadge])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center
        return stack
    }()

    /// Blur overlay that obscures the banner image when Blur NSFW is on.
    ///
    /// Deliberately kept a `UIBlurEffect` in the Liquid Glass conversion
    /// (Task 16): `blurBanner` (see `configure(...)`) is driven by
    /// `viewModel.isNsfw && preferencesService.blurNsfw` — this is a content
    /// obscurer for the NSFW banner, the same job as `NsfwBlurOverlayView`,
    /// not a legibility scrim or chrome. Glass is translucent by design and
    /// would defeat the point of hiding the image.
    private lazy var bannerBlurView: UIVisualEffectView = {
        let effect = UIBlurEffect(style: .systemThickMaterial)
        let view = UIVisualEffectView(effect: effect)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = false
        view.isHidden = true
        return view
    }()

    /// Groups the banner image with its NSFW blur overlay so both are
    /// captured together as the extension view's `contentView`. If the blur
    /// overlay stayed a sibling of the extension view instead, the
    /// mirrored/blurred copy that extends under the sidebar would be built
    /// from the raw (un-blurred) banner image, leaking it around the blur.
    private lazy var bannerContentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.clipsToBounds = true
        view.addSubview(bannerImageView)
        view.addSubview(bannerBlurView)
        NSLayoutConstraint.activate([
            bannerImageView.topAnchor.constraint(equalTo: view.topAnchor),
            bannerImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bannerImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bannerImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            bannerBlurView.topAnchor.constraint(equalTo: view.topAnchor),
            bannerBlurView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bannerBlurView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bannerBlurView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        return view
    }()

    /// Extends the banner beneath an adjacent sidebar/inspector in the iPad
    /// split (`UIBackgroundExtensionView`, iOS 26+): mirrors and blurs the
    /// banner into the region a plain view would otherwise just stop at, so
    /// it reads as continuing under the sidebar rather than ending abruptly
    /// at the detail column's edge. A no-op with no adjacent sidebar (iPhone,
    /// or when this header is itself the primary/leading column).
    ///
    /// It is also a no-op on iPad today: `MainWindowSplitViewController` sets
    /// `preferredSplitBehavior = .tile`, and tiled columns do not overlap, so
    /// there is no region to extend into. Kept deliberately — see
    /// `docs/adr/0002-liquid-glass-adoption.md`.
    private lazy var bannerExtensionView: UIBackgroundExtensionView = {
        let view = UIBackgroundExtensionView()
        view.translatesAutoresizingMaskIntoConstraints = false
        // Placing the content view explicitly (rather than the `true` default)
        // is a deliberate workaround, not a style choice: with the default
        // automatic placement, hosting this view inside a `UITableView`
        // scrolling header sized via `systemLayoutSizeFitting`
        // (`PostListViewController.layoutScrollingHeaderIfNeeded`) reliably
        // hung the app (confirmed with a UI test, iOS 26.3 simulator) —
        // `systemLayoutSizeFitting` never returns because whatever the
        // automatic placement does internally never completes outside a live
        // display cycle. Pinning to `safeAreaLayoutGuide` ourselves reproduces
        // the same visual placement without going through that path.
        view.automaticallyPlacesContentView = false
        view.contentView = bannerContentView
        NSLayoutConstraint.activate([
            bannerContentView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            bannerContentView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            bannerContentView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            bannerContentView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
        return view
    }()

    private lazy var separator: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .separator
        return view
    }()

    /// Hairline height, kept as a property so `layoutSubviews()` can re-resolve
    /// it against the current display scale (a value baked in once at `setup()`
    /// would go stale if the window moved to a display with a different scale,
    /// e.g. under iPhone Mirroring).
    private lazy var separatorHeightConstraint = separator.heightAnchor.constraint(
        equalToConstant: 1 / traitCollection.displayScale
    )

    // MARK: Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Re-evaluate the border color in case the trait collection (light /
        // dark) changed.
        iconImageView.layer.borderColor = UIColor.systemBackground.cgColor
        separatorHeightConstraint.constant = 1 / traitCollection.displayScale
    }

    private func setup() {
        backgroundColor = .systemBackground

        addSubview(bannerExtensionView)
        addSubview(iconImageView)
        addSubview(titleLabel)
        addSubview(badgeStack)
        addSubview(handleLabel)

        handleLabel.isUserInteractionEnabled = true
        handleLabel.accessibilityTraits = .button
        handleLabel.accessibilityHint = NSLocalizedString(
            "Opens the instance detail",
            comment: "Accessibility hint for the community handle label that taps through to instance detail"
        )
        let handleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTapped))
        handleLabel.addGestureRecognizer(handleTapGesture)

        addSubview(metaStack)
        addSubview(subscribeButton)
        addSubview(descriptionView)
        addSubview(separator)

        let margin: CGFloat = 16

        NSLayoutConstraint.activate([
            bannerExtensionView.topAnchor.constraint(equalTo: topAnchor),
            bannerExtensionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bannerExtensionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            bannerExtensionView.heightAnchor.constraint(equalToConstant: bannerHeight),

            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            iconImageView.centerYAnchor.constraint(equalTo: bannerExtensionView.bottomAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: iconSize),
            iconImageView.heightAnchor.constraint(equalToConstant: iconSize),

            subscribeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),
            subscribeButton.topAnchor.constraint(equalTo: bannerExtensionView.bottomAnchor, constant: 8),

            titleLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -margin),

            // Badge stack (NSFW + meta pills): vertically centered on the title
            // label, leading edge just after the title, with a trailing cap so
            // the stack never overflows into the trailing margin on narrow
            // screens. Each pill keeps its own min-width/height so it still
            // reads as a pill once the stack sizes it in.
            badgeStack.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 6),
            badgeStack.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            badgeStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -margin),

            nsfwBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 36),
            nsfwBadge.heightAnchor.constraint(equalToConstant: 16),
            metaBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 36),
            metaBadge.heightAnchor.constraint(equalToConstant: 16),

            handleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            handleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            handleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),

            metaStack.topAnchor.constraint(equalTo: handleLabel.bottomAnchor, constant: 6),
            metaStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            metaStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),

            descriptionView.topAnchor.constraint(equalTo: metaStack.bottomAnchor, constant: 12),
            descriptionView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            descriptionView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),

            separator.topAnchor.constraint(equalTo: descriptionView.bottomAnchor, constant: 12),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separatorHeightConstraint,
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    // MARK: Configuration

    func configure(
        title: String,
        qualifiedName: String,
        subscribersText: String,
        postsText: String,
        vitalityText: String?,
        descriptionMarkdown: String?,
        subscribed: CommunitySubscribedState,
        isNsfw: Bool,
        isMeta: Bool,
        blurBanner: Bool
    ) {
        titleLabel.text = title
        handleLabel.text = qualifiedName

        let subscribers = String(
            format: NSLocalizedString("%@ subscribers", comment: "Community header subscriber count"),
            subscribersText
        )
        let posts = String(
            format: NSLocalizedString("%@ posts", comment: "Community header post count"),
            postsText
        )
        statsLabel.text = "\(subscribers)  ·  \(posts)"

        vitalityLabel.text = vitalityText
        vitalityLabel.isHidden = vitalityText == nil

        nsfwBadge.isHidden = !isNsfw
        metaBadge.isHidden = !isMeta
        bannerBlurView.isHidden = !blurBanner

        configureDescription(markdown: descriptionMarkdown)
        configureSubscribeButton(subscribed: subscribed)
    }

    private func configureDescription(markdown: String?) {
        guard let markdown, !markdown.isEmpty else {
            descriptionView.setBlocks([])
            descriptionView.isHidden = true
            return
        }
        descriptionView.isHidden = false
        // Set the loader before the blocks so inline images start loading as the
        // image blocks are built.
        if let imageService {
            descriptionView.imageLoader = { [imageService] url in
                for await state in imageService.fetch(url) {
                    if case let .ready(image) = state { return image }
                }
                return nil
            }
        }
        // Parse off the main thread, then render the blocks back on main. The
        // token drops a stale parse from an earlier configure landing late.
        descriptionToken &+= 1
        let token = descriptionToken
        Task { [weak self] in
            await MarkdownBlockCache.shared.prewarm(markdown)
            guard let self, token == descriptionToken else { return }
            descriptionView.setBlocks(MarkdownBlockCache.shared.blocks(for: markdown))
            // `setBlocks` only swaps the stacked block views; it does not fire
            // `onContentSizeChange`. Force a layout pass so the new content height
            // is valid, then ask the host to re-measure the scrolling table header
            // (a `tableHeaderView` does not self-size). Without this the header
            // keeps the too-short height it was measured at before the off-main
            // parse landed, squishing/clipping the description.
            layoutIfNeeded()
            onDescriptionHeightChanged?()
        }
    }

    private func configureSubscribeButton(subscribed: CommunitySubscribedState) {
        var config = subscribeButton.configuration ?? .filled()
        // Default: no secondary line. Only `.denied` sets one, and the config is
        // reused across reconfigures, so the subtitle must be cleared for every
        // other state (otherwise a stale "Request declined" would linger).
        config.subtitle = nil
        // A bespoke VoiceOver label is set only where the visible text alone isn't
        // enough (`.denied`); nil lets UIKit derive it from the title/subtitle.
        var accessibilityLabel: String?

        // Title + symbol come from the shared helper (also used by
        // `SearchCommunityCell`) so the two surfaces never drift on copy/iconography.
        config.title = CommunitySubscribeButtonLabel.title(for: subscribed)
        config.image = UIImage(systemName: CommunitySubscribeButtonLabel.symbol(for: subscribed))
        subscribeButton.isEnabled = true

        switch subscribed {
        case .notSubscribed:
            config.baseBackgroundColor = .systemBlue
            config.baseForegroundColor = .white
        case .denied:
            // v4: the moderators denied the follow request. The primary action stays
            // Subscribe so the user can re-request, but a "Request declined" subtitle
            // and an explicit VoiceOver label distinguish it from a community never
            // subscribed to — the prior rejection isn't silently hidden.
            config.subtitle = NSLocalizedString("Request declined", comment: "Community subscribe button secondary line when the moderators denied a prior follow request")
            config.baseBackgroundColor = .systemBlue
            config.baseForegroundColor = .white
            accessibilityLabel = NSLocalizedString(
                "Subscribe. Your previous request was declined.",
                comment: "VoiceOver label for the community subscribe button after the moderators denied a follow request"
            )
        case .subscribed:
            config.baseBackgroundColor = .secondarySystemBackground
            config.baseForegroundColor = .label
        case .pending:
            config.baseBackgroundColor = .secondarySystemBackground
            config.baseForegroundColor = .secondaryLabel
        case .approvalRequired:
            // v4: the community gates joining behind moderator approval and the
            // request is awaiting a decision. Distinct from the momentary
            // just-tapped Pending — this is the server's confirmed answer.
            config.baseBackgroundColor = .secondarySystemBackground
            config.baseForegroundColor = .secondaryLabel
        }
        config.imagePadding = 4
        subscribeButton.configuration = config
        subscribeButton.accessibilityLabel = accessibilityLabel
    }

    // MARK: Images

    func setBannerImage(_ image: UIImage?) {
        bannerImageView.image = image
    }

    func setIconImage(_ image: UIImage?) {
        guard let image else { return }
        iconImageView.image = image
    }

    // MARK: Zoom transition

    /// The on-screen view a media viewer should zoom from / back to for a
    /// description image with `imageURL`, or nil when that image is not
    /// currently rendered (description rebuilt, image not yet loaded, or
    /// scrolled away).
    func zoomSourceView(forImageURL imageURL: URL) -> UIView? {
        descriptionView.zoomSourceView(forImageURL: imageURL)
    }

    @objc
    private func subscribeButtonTapped() {
        subscribeTapped?()
    }

    @objc
    private func handleTapped() {
        onInstanceTapped?()
    }
}

extension CommunityHeaderView: MarkdownBodyDelegate {
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
