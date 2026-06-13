//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudUIKit
import UIKit

/// The sign-in gate shown when a signed-out user taps a write action (vote,
/// comment, save, subscribe…). Mirrors the Claude Design `SignInGate` sheet: a
/// dark sheet with a grabber, an accent-ringed up-arrow, "Sign in to <action>",
/// a one-line rationale, and Create account / Log in / Not now.
///
/// Both auth buttons hand off through `onSignIn` (the presenter routes to the
/// Account tab, which offers log-in and sign-up); "Not now" just dismisses.
final class SignInGateViewController: UIViewController {
    private let promptTitle: String
    private let onSignIn: () -> Void
    private var didConfigureDetent = false

    /// - Parameter title: the already-localized prompt, e.g. "Sign in to vote".
    init(title: String, onSignIn: @escaping () -> Void) {
        promptTitle = title
        self.onSignIn = onSignIn
        super.init(nibName: nil, bundle: nil)

        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 22
            sheet.detents = [.medium()]
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private lazy var iconRing: UIView = {
        let accent = ThemeManager.currentAccentColor
        let ring = UIView()
        ring.translatesAutoresizingMaskIntoConstraints = false
        ring.backgroundColor = accent.withAlphaComponent(0.12)
        ring.layer.cornerRadius = 32
        ring.layer.borderWidth = 1.5
        ring.layer.borderColor = accent.withAlphaComponent(0.27).cgColor

        let arrow = UIImageView(image: UIImage(
            systemName: "arrow.up",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 28, weight: .bold)
        ))
        arrow.tintColor = accent
        arrow.translatesAutoresizingMaskIntoConstraints = false
        ring.addSubview(arrow)

        NSLayoutConstraint.activate([
            ring.widthAnchor.constraint(equalToConstant: 64),
            ring.heightAnchor.constraint(equalToConstant: 64),
            arrow.centerXAnchor.constraint(equalTo: ring.centerXAnchor),
            arrow.centerYAnchor.constraint(equalTo: ring.centerYAnchor),
        ])
        return ring
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.text = promptTitle
        label.font = .systemFont(ofSize: 20, weight: .heavy)
        label.textColor = .label
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private lazy var bodyLabel: UILabel = {
        let label = UILabel()
        label.text = NSLocalizedString(
            "Voting, commenting and subscribing need an account. It takes under a minute — browse all you like without one.",
            comment: "Sign-in gate explanatory body"
        )
        label.font = .systemFont(ofSize: 14, weight: .regular)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        // The gate is a dark-context sheet; match the design's near-black surface.
        view.backgroundColor = UIColor(red: 0.102, green: 0.102, blue: 0.110, alpha: 1)

        let createButton = makeFilledButton(
            title: NSLocalizedString("Create account", comment: "Sign-in gate primary button"),
            action: #selector(signInTapped)
        )
        let loginButton = makeNeutralButton(
            title: NSLocalizedString("Log in", comment: "Sign-in gate secondary button"),
            action: #selector(signInTapped)
        )
        let notNowButton = makePlainButton(
            title: NSLocalizedString("Not now", comment: "Sign-in gate dismiss button"),
            action: #selector(notNowTapped)
        )

        // Centered hero (ring + copy) over the full-width action buttons.
        let ringRow = UIStackView(arrangedSubviews: [iconRing])
        ringRow.axis = .horizontal
        ringRow.alignment = .center
        ringRow.distribution = .equalCentering

        let hero = UIStackView(arrangedSubviews: [ringRow, titleLabel, bodyLabel])
        hero.axis = .vertical
        hero.alignment = .fill
        hero.spacing = 12
        hero.setCustomSpacing(16, after: ringRow)

        let stack = UIStackView(arrangedSubviews: [hero, createButton, loginButton, notNowButton])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 10
        stack.setCustomSpacing(22, after: hero)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -22),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            createButton.heightAnchor.constraint(equalToConstant: 50),
            loginButton.heightAnchor.constraint(equalToConstant: 50),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard
            let sheet = sheetPresentationController,
            !didConfigureDetent,
            let stack = view.subviews.first,
            view.bounds.width > 0
        else { return }
        didConfigureDetent = true

        let fitting = stack.systemLayoutSizeFitting(
            CGSize(width: view.bounds.width - 44, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        let total = fitting + 18 + 16 + 24 + view.safeAreaInsets.bottom

        sheet.animateChanges {
            sheet.detents = [.custom { context in min(total, context.maximumDetentValue * 0.9) }]
        }
    }

    private func makeFilledButton(title: String, action: Selector) -> UIButton {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.baseBackgroundColor = ThemeManager.currentAccentColor
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .fixed
        configuration.background.cornerRadius = 14
        let button = UIButton(configuration: configuration)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func makeNeutralButton(title: String, action: Selector) -> UIButton {
        var configuration = UIButton.Configuration.gray()
        configuration.title = title
        configuration.baseForegroundColor = .label
        configuration.cornerStyle = .fixed
        configuration.background.cornerRadius = 14
        configuration.background.backgroundColor = UIColor(white: 1, alpha: 0.11)
        let button = UIButton(configuration: configuration)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func makePlainButton(title: String, action: Selector) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.baseForegroundColor = .secondaryLabel
        let button = UIButton(configuration: configuration)
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    @objc
    private func signInTapped() {
        let onSignIn = onSignIn
        dismiss(animated: true) { onSignIn() }
    }

    @objc
    private func notNowTapped() {
        dismiss(animated: true)
    }
}
