//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudUIKit
import UIKit

/// Centered placeholder shown in the post-detail column when the post no longer
/// exists on the server (removed / deleted / de-federated). Replaces the stale
/// cached content. See `PostUnavailableReason` for copy + gating.
final class PostUnavailableViewController: UIViewController {
    private let reason: PostUnavailableReason

    init(reason: PostUnavailableReason) {
        self.reason = reason
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background

        let imageView = UIImageView(image: UIImage(systemName: reason.symbolName))
        imageView.tintColor = .tertiaryLabel
        imageView.contentMode = .scaleAspectFit
        imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 44, weight: .light)
        imageView.isAccessibilityElement = false

        let titleLabel = UILabel()
        titleLabel.text = reason.title
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .secondaryLabel
        titleLabel.adjustsFontForContentSizeCategory = true

        let stack = UIStackView(arrangedSubviews: [imageView, titleLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        if let subtitle = reason.subtitle {
            let subtitleLabel = UILabel()
            subtitleLabel.text = subtitle
            subtitleLabel.textAlignment = .center
            subtitleLabel.numberOfLines = 0
            subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
            subtitleLabel.textColor = .tertiaryLabel
            subtitleLabel.adjustsFontForContentSizeCategory = true
            stack.addArrangedSubview(subtitleLabel)
        }

        // One VoiceOver element reading the full message.
        stack.isAccessibilityElement = true
        stack.accessibilityTraits = .staticText
        stack.accessibilityLabel = [reason.title, reason.subtitle].compactMap { $0 }.joined(separator: ". ")

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
    }
}
