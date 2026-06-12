//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUIKit
import UIKit

/// The signed-out (anonymous) state of the Account tab: a clean, designed
/// call-to-action to Log in or Sign up. Browsing as a guest is already the
/// default, so this screen explains that and offers the two ways to get an
/// account.
final class AccountSignedOutViewController: UIViewController {
    var loginTapped: (() -> Void)?
    var signUpTapped: (() -> Void)?

    private lazy var iconView: UIImageView = {
        let view = UIImageView(image: UIImage(systemName: "person.crop.circle.badge.questionmark"))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFit
        view.tintColor = .tertiaryLabel
        view.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 64, weight: .regular)
        return view
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = NSLocalizedString("You're browsing as a guest", comment: "Signed-out account title")
        label.font = UIFont.boldSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .title2).pointSize)
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private lazy var subtitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = NSLocalizedString(
            "Log in or sign up to vote, comment, subscribe, and save posts.",
            comment: "Signed-out account subtitle"
        )
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private lazy var loginButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = NSLocalizedString("Log in", comment: "Signed-out account log-in button")
        config.cornerStyle = .medium
        config.buttonSize = .large
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(didTapLogin), for: .touchUpInside)
        return button
    }()

    private lazy var signUpButton: UIButton = {
        var config = UIButton.Configuration.tinted()
        config.title = NSLocalizedString("Sign up", comment: "Signed-out account sign-up button")
        config.cornerStyle = .medium
        config.buttonSize = .large
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(didTapSignUp), for: .touchUpInside)
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background

        let stack = UIStackView(arrangedSubviews: [
            iconView,
            titleLabel,
            subtitleLabel,
            loginButton,
            signUpButton,
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 12
        stack.setCustomSpacing(20, after: iconView)
        stack.setCustomSpacing(28, after: subtitleLabel)

        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor, constant: -16),

            iconView.heightAnchor.constraint(equalToConstant: 72),
        ])
    }

    @objc
    private func didTapLogin() {
        loginTapped?()
    }

    @objc
    private func didTapSignUp() {
        signUpTapped?()
    }
}
