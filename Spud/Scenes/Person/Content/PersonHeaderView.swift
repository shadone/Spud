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

/// Account-status info shown in the person header beyond the basic profile
/// fields. All optional; the default value renders nothing.
struct PersonHeaderStatus: Equatable {
    /// A user-facing instance-ban string (with expiry) or nil when not banned.
    var banText: String?
    var isDeleted: Bool = false
    var isBot: Bool = false
    var isAdmin: Bool = false
    var matrixUserId: String?

    static let none = PersonHeaderStatus()
}

/// A `UILabel` that draws with insets — used for the small status pills.
private final class PillLabel: UILabel {
    var insets = UIEdgeInsets(top: 1, left: 5, bottom: 1, right: 5)

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

/// Apollo-style person header: an optional instance-ban / deleted banner, an
/// optional banner image, an overlapping circular avatar, the display name with
/// Bot / Admin badges, the "@name@instance" handle, a stats line (karma + cake
/// day), an optional Matrix contact row, and a markdown bio.
///
/// Layout-only; the owning view controller drives it via `configure(...)`,
/// loads images, and wires the bio-link and matrix-tap callbacks.
final class PersonHeaderView: UIView {
    /// Fired when a link inside the markdown bio is tapped (raw renderer URL;
    /// the host resolves `spud-markdown://` mentions).
    var onBodyLinkTapped: ((URL) -> Void)?
    /// Fired when a loaded inline bio image is tapped (zoom).
    var onBodyImageTapped: ((_ url: URL, _ altText: String?, _ sourceRect: CGRect) -> Void)?
    /// Fired when an inline bio video tile is tapped.
    var onBodyVideoTapped: ((URL) -> Void)?
    /// Fired when an inline bio audio tile is tapped.
    var onBodyAudioTapped: ((URL) -> Void)?
    /// Fired when the Matrix contact row is tapped (the host copies it).
    var onMatrixTapped: ((String) -> Void)?

    /// The image loader used for inline bio images. Set by the owning view
    /// controller before `configure(...)`.
    var imageService: ImageServiceType?

    /// Fired when an inline bio image finishes loading and the bio's height
    /// changes, so the host can re-lay-out around the taller header.
    var onBodyImageLoaded: (() -> Void)?

    private let bannerHeight: CGFloat = 100
    private let avatarSize: CGFloat = 72
    private let margin: CGFloat = 16

    private var matrixUserId: String?

    // MARK: Subviews

    private lazy var statusBannerIcon: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.tintColor = .white
        view.contentMode = .scaleAspectFit
        view.setContentHuggingPriority(.required, for: .horizontal)
        return view
    }()

    private lazy var statusBannerLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .white
        label.numberOfLines = 0
        return label
    }()

    private lazy var statusBannerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.accessibilityIdentifier = "statusBanner"
        view.isAccessibilityElement = true

        let stack = UIStackView(arrangedSubviews: [statusBannerIcon, statusBannerLabel])
        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        let bottom = stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6)
        bottom.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -margin),
            bottom,
        ])
        return view
    }()

    private lazy var statusBannerZeroHeight = statusBannerView.heightAnchor.constraint(equalToConstant: 0)

    private lazy var bannerImageView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.backgroundColor = .secondarySystemBackground
        return view
    }()

    private lazy var avatarImageView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.layer.cornerRadius = avatarSize / 2
        view.layer.borderWidth = 3
        view.layer.borderColor = UIColor.systemBackground.cgColor
        view.backgroundColor = .tertiarySystemBackground
        view.image = UIImage(systemName: "person.crop.circle.fill")
        view.tintColor = .secondaryLabel
        return view
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.boldSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .title2).pointSize)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 2
        return label
    }()

    private lazy var badgeRow: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center
        return stack
    }()

    private lazy var handleLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        return label
    }()

    private lazy var statsLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        return label
    }()

    private lazy var matrixLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .link
        label.numberOfLines = 1
        label.accessibilityIdentifier = "matrix"
        label.isUserInteractionEnabled = true
        label.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(matrixTapped)))
        return label
    }()

    private lazy var bodyView: MarkdownBodyView = {
        let context = MarkdownContext(kind: .post, textScale: 0, density: .comfortable)
        let view = MarkdownBodyView(context: context)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.accessibilityIdentifier = "bio"
        view.delegate = self
        view.onContentSizeChange = { [weak self] in
            self?.onBodyImageLoaded?()
        }
        return view
    }()

    /// The labels above the bio. Stacked (not the bio) so the badge / matrix
    /// rows collapse cleanly when absent — a stack only spaces visible arranged
    /// subviews — while the bio keeps its original direct constraints so its
    /// inline-image rendering is byte-for-byte unchanged from before.
    private lazy var topStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [
            titleLabel, badgeRow, handleLabel, statsLabel, matrixLabel,
        ])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        // Spacings match the original chain so the no-status layout is unchanged.
        stack.setCustomSpacing(2, after: titleLabel)
        stack.setCustomSpacing(6, after: badgeRow)
        stack.setCustomSpacing(6, after: handleLabel)
        stack.setCustomSpacing(12, after: statsLabel)
        return stack
    }()

    private lazy var separator: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .separator
        return view
    }()

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
        avatarImageView.layer.borderColor = UIColor.systemBackground.cgColor
    }

    private func setup() {
        backgroundColor = Theme.background

        addSubview(statusBannerView)
        addSubview(bannerImageView)
        addSubview(avatarImageView)
        addSubview(topStack)
        addSubview(bodyView)
        addSubview(separator)

        NSLayoutConstraint.activate([
            statusBannerView.topAnchor.constraint(equalTo: topAnchor),
            statusBannerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            statusBannerView.trailingAnchor.constraint(equalTo: trailingAnchor),

            bannerImageView.topAnchor.constraint(equalTo: statusBannerView.bottomAnchor),
            bannerImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bannerImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            bannerImageView.heightAnchor.constraint(equalToConstant: bannerHeight),

            avatarImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            avatarImageView.centerYAnchor.constraint(equalTo: bannerImageView.bottomAnchor),
            avatarImageView.widthAnchor.constraint(equalToConstant: avatarSize),
            avatarImageView.heightAnchor.constraint(equalToConstant: avatarSize),

            topStack.topAnchor.constraint(equalTo: avatarImageView.bottomAnchor, constant: 8),
            topStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            topStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),

            bodyView.topAnchor.constraint(equalTo: topStack.bottomAnchor, constant: 12),
            bodyView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            bodyView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),

            separator.topAnchor.constraint(equalTo: bodyView.bottomAnchor, constant: 12),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        hideBanner()
    }

    // MARK: Configuration

    func configure(
        title: String,
        handle: String,
        statsText: String,
        bioMarkdown: String?,
        status: PersonHeaderStatus = .none
    ) {
        titleLabel.text = title
        handleLabel.text = handle
        statsLabel.text = statsText
        configureBio(markdown: bioMarkdown)
        configureStatus(status)
    }

    private func configureStatus(_ status: PersonHeaderStatus) {
        // Banner: a ban takes precedence over a self-deleted account.
        if let banText = status.banText {
            showBanner(text: banText, background: .systemRed, symbol: "exclamationmark.triangle.fill")
        } else if status.isDeleted {
            showBanner(
                text: NSLocalizedString("Account deleted", comment: "Profile status banner: the user deleted their account"),
                background: .systemGray,
                symbol: "person.fill.xmark"
            )
        } else {
            hideBanner()
        }

        for view in badgeRow.arrangedSubviews {
            badgeRow.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        if status.isAdmin {
            badgeRow.addArrangedSubview(makePill(
                text: NSLocalizedString("ADMIN", comment: "Profile badge: instance admin"),
                color: .systemIndigo
            ))
        }
        if status.isBot {
            badgeRow.addArrangedSubview(makePill(
                text: NSLocalizedString("BOT", comment: "Profile badge: bot account"),
                color: .systemGray
            ))
        }
        if !badgeRow.arrangedSubviews.isEmpty {
            let spacer = UIView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            badgeRow.addArrangedSubview(spacer)
        }
        badgeRow.isHidden = badgeRow.arrangedSubviews.isEmpty

        matrixUserId = status.matrixUserId
        if let matrix = status.matrixUserId {
            matrixLabel.text = String(
                format: NSLocalizedString("Matrix · %@", comment: "Profile contact row; %@ is the matrix id"),
                matrix
            )
            matrixLabel.isHidden = false
        } else {
            matrixLabel.isHidden = true
        }
    }

    private func showBanner(text: String, background: UIColor, symbol: String) {
        statusBannerView.isHidden = false
        statusBannerZeroHeight.isActive = false
        statusBannerView.backgroundColor = background
        statusBannerIcon.image = UIImage(systemName: symbol)
        statusBannerLabel.text = text
        statusBannerView.accessibilityLabel = text
    }

    private func hideBanner() {
        statusBannerView.isHidden = true
        statusBannerZeroHeight.isActive = true
    }

    private func makePill(text: String, color: UIColor) -> UILabel {
        let label = PillLabel()
        label.text = text
        label.font = .systemFont(ofSize: 9, weight: .heavy)
        label.textColor = .white
        label.backgroundColor = color
        label.layer.cornerRadius = 4
        label.layer.masksToBounds = true
        label.accessibilityIdentifier = "badge.\(text)"
        return label
    }

    @objc
    private func matrixTapped() {
        guard let matrixUserId else { return }
        onMatrixTapped?(matrixUserId)
    }

    private func configureBio(markdown: String?) {
        guard let markdown, !markdown.isEmpty else {
            bodyView.setBlocks([])
            bodyView.isHidden = true
            return
        }
        bodyView.isHidden = false
        // Set the loader before the blocks so inline images start loading as the
        // image blocks are built.
        if let imageService {
            bodyView.imageLoader = { [imageService] url in
                for await state in imageService.fetch(url) {
                    if case let .ready(image) = state { return image }
                }
                return nil
            }
        }
        bodyView.setBlocks(MarkdownBlockCache.shared.blocks(for: markdown))
    }

    // MARK: Images

    func setBannerImage(_ image: UIImage?) {
        bannerImageView.image = image
    }

    func setAvatarImage(_ image: UIImage?) {
        guard let image else { return }
        avatarImageView.image = image
    }
}

extension PersonHeaderView: MarkdownBodyDelegate {
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
