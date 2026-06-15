//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// First-launch Welcome screen. Brand mark, wordmark, tagline and a single
/// "Get started" CTA. Owns no dependencies; the host wires `onGetStarted` to
/// push the instance picker. Matches the onboarding design's Welcome screen
/// minus the (removed) "Browse without an account" secondary button.
final class OnboardingWelcomeViewController: UIViewController {
    /// Invoked when the user taps "Get started".
    var onGetStarted: (() -> Void)?

    private let accentGradient = CAGradientLayer()

    private lazy var logoImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "AppIconPreview-Default"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 28
        imageView.layer.cornerCurve = .continuous
        return imageView
    }()

    private lazy var wordmarkLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Spud"
        label.font = .systemFont(ofSize: 40, weight: .heavy)
        label.textColor = .label
        label.textAlignment = .center
        return label
    }()

    private lazy var taglineLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = NSLocalizedString(
            "Communities worth your time.",
            comment: "Onboarding welcome tagline"
        )
        label.font = .systemFont(ofSize: 19, weight: .semibold)
        label.textColor = .label
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private lazy var bodyLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = NSLocalizedString(
            "Thousands of communities, real threaded discussion, and a feed you actually control — no ads, no algorithm.",
            comment: "Onboarding welcome body"
        )
        label.font = .systemFont(ofSize: 15, weight: .regular)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private lazy var getStartedButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.title = NSLocalizedString("Get started", comment: "Onboarding primary CTA")
        configuration.cornerStyle = .large
        configuration.contentInsets = .init(top: 15, leading: 16, bottom: 15, trailing: 16)
        let button = UIButton(configuration: configuration)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(getStartedTapped), for: .touchUpInside)
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        accentGradient.type = .radial
        view.layer.insertSublayer(accentGradient, at: 0)

        let textStack = UIStackView(arrangedSubviews: [wordmarkLabel, taglineLabel, bodyLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.alignment = .center
        textStack.spacing = 12

        view.addSubview(logoImageView)
        view.addSubview(textStack)
        view.addSubview(getStartedButton)

        NSLayoutConstraint.activate([
            logoImageView.widthAnchor.constraint(equalToConstant: 96),
            logoImageView.heightAnchor.constraint(equalToConstant: 96),
            logoImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            logoImageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 96),

            textStack.topAnchor.constraint(equalTo: logoImageView.bottomAnchor, constant: 26),
            textStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 34),
            textStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -34),

            getStartedButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            getStartedButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            getStartedButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        accentGradient.frame = view.bounds
        let accent = (view.tintColor ?? .systemBlue).withAlphaComponent(0.18)
        accentGradient.colors = [accent.cgColor, UIColor.clear.cgColor]
        // Radial gradient centred near the top, fading out by ~58%.
        accentGradient.startPoint = CGPoint(x: 0.5, y: 0.26)
        accentGradient.endPoint = CGPoint(x: 1.08, y: 0.84)
    }

    @objc
    private func getStartedTapped() {
        onGetStarted?()
    }
}
