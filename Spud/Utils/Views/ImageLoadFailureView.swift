//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// The image-load failure "Plate" shown in the post-detail header when a post's
/// image can't be fetched.
///
/// An elevated `secondarySystemBackground` panel that takes the image's place:
/// a monochrome broken-image glyph, a short message, and Retry / Open-in-browser
/// actions. The retrying state swaps the glyph for an activity indicator and
/// hides the actions. Matches the Scout "Plate" redlines — 208pt minimum height,
/// accent-tinted actions, Dynamic-Type type styles. Pure view: it exposes
/// `onRetry` / `onOpenInBrowser` and holds no loading logic itself.
final class ImageLoadFailureView: UIView {
    /// Invoked when Retry is tapped. The owner re-requests the image.
    var onRetry: (() -> Void)?
    /// Invoked when Open in browser is tapped.
    var onOpenInBrowser: (() -> Void)?

    /// The plate's minimum height; it grows past this for large Dynamic Type.
    static let minimumHeight: CGFloat = 208

    private let glyphView: UIImageView = {
        let size = UIImage.SymbolConfiguration(pointSize: 44)
        let palette = UIImage.SymbolConfiguration(paletteColors: [.quaternaryLabel, .secondaryLabel])
        let imageView = UIImageView(image: UIImage(systemName: "photo.badge.exclamationmark"))
        imageView.preferredSymbolConfiguration = size.applying(palette)
        imageView.contentMode = .center
        imageView.isAccessibilityElement = false
        return imageView
    }()

    private let spinner: UIActivityIndicatorView = {
        let view = UIActivityIndicatorView(style: .large)
        view.color = .tertiaryLabel
        view.hidesWhenStopped = true
        view.isAccessibilityElement = false
        return view
    }()

    private let messageLabel: UILabel = {
        let label = UILabel()
        label.font = ImageLoadFailureView.subheadlineSemibold
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private lazy var retryButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.title = NSLocalizedString("Retry", comment: "Button to retry a failed image load")
        configuration.image = UIImage(systemName: "arrow.clockwise")
        configuration.imagePadding = 7
        configuration.cornerStyle = .fixed
        configuration.background.cornerRadius = 10
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 18)
        configuration.titleTextAttributesTransformer = ImageLoadFailureView.buttonTitleTransformer
        let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
            self?.onRetry?()
        })
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityIdentifier = "imageLoadFailureRetry"
        button.heightAnchor.constraint(equalToConstant: 38).isActive = true
        return button
    }()

    private lazy var openButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.title = NSLocalizedString("Open in browser", comment: "Button to open a failed image in the browser")
        configuration.image = UIImage(systemName: "arrow.up.right")
        configuration.imagePadding = 6
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)
        configuration.titleTextAttributesTransformer = ImageLoadFailureView.buttonTitleTransformer
        let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
            self?.onOpenInBrowser?()
        })
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 38).isActive = true
        return button
    }()

    /// Plain container so the two buttons keep their intrinsic widths and a fixed
    /// 6pt gap; a UIStackView here would stretch them to the column width.
    private lazy var actionsContainer: UIView = {
        let container = UIView()
        container.addSubview(retryButton)
        container.addSubview(openButton)
        NSLayoutConstraint.activate([
            retryButton.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            retryButton.topAnchor.constraint(equalTo: container.topAnchor),
            retryButton.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            openButton.leadingAnchor.constraint(equalTo: retryButton.trailingAnchor, constant: 6),
            openButton.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            openButton.centerYAnchor.constraint(equalTo: retryButton.centerYAnchor),
            openButton.topAnchor.constraint(greaterThanOrEqualTo: container.topAnchor),
            openButton.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor),
        ])
        return container
    }()

    private lazy var contentStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [glyphView, spinner, messageLabel, actionsContainer])
        stack.axis = .vertical
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setCustomSpacing(14, after: glyphView)
        stack.setCustomSpacing(14, after: spinner)
        stack.setCustomSpacing(16, after: messageLabel)
        return stack
    }()

    private let hairline: UIView = {
        let view = UIView()
        view.backgroundColor = .separator
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = .secondarySystemBackground
        addSubview(contentStack)
        addSubview(hairline)

        NSLayoutConstraint.activate([
            contentStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            contentStack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 20),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -20),

            messageLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -32),

            hairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            hairline.bottomAnchor.constraint(equalTo: bottomAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 0.5),
        ])

        setRetrying(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Toggles between the default failure state (glyph + message + actions) and
    /// the retrying state (activity indicator + "Loading image…", no actions).
    func setRetrying(_ retrying: Bool) {
        glyphView.isHidden = retrying
        actionsContainer.isHidden = retrying
        spinner.isHidden = !retrying
        if retrying {
            spinner.startAnimating()
        } else {
            spinner.stopAnimating()
        }
        messageLabel.text = retrying
            ? NSLocalizedString("Loading image…", comment: "Shown while retrying a failed image load")
            : NSLocalizedString("Image couldn’t load", comment: "Shown when a post image fails to load")
    }

    private static var subheadlineSemibold: UIFont {
        UIFontMetrics(forTextStyle: .subheadline)
            .scaledFont(for: .systemFont(ofSize: 15, weight: .semibold))
    }

    private static let buttonTitleTransformer = UIConfigurationTextAttributesTransformer { incoming in
        var outgoing = incoming
        outgoing.font = subheadlineSemibold
        return outgoing
    }
}
