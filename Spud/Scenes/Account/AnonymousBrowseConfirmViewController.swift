//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import SpudUIKit
import SpudUtilKit
import UIKit

/// Read-only "browse anonymously" confirmation. Pushed from the login screen's
/// "Browse <instance> anonymously" row before actually signing in as a
/// signed-out account. Matches the Spud Design `AnonConfirm` mockup: a centred
/// globe tile, a "Browse <host>" title, an explanatory body, a "reading from
/// <host> · anonymous" chip, and — pinned near the bottom — a "Start browsing"
/// primary CTA plus a "Pick a different server" ghost button.
final class AnonymousBrowseConfirmViewController: UIViewController {
    typealias Dependencies = HasAccountService
    private let dependencies: Dependencies

    private var accountService: AccountServiceType {
        dependencies.accountService
    }

    private let instance: InstanceActorId
    private let hostname: String

    // MARK: UI Properties

    /// The 76pt rounded-square tile holding the large globe glyph, tinted with
    /// the app accent.
    private lazy var globeTile: UIView = {
        let tile = UIView()
        tile.translatesAutoresizingMaskIntoConstraints = false
        tile.backgroundColor = .secondarySystemBackground
        tile.layer.cornerRadius = 22
        tile.layer.cornerCurve = .continuous
        return tile
    }()

    private lazy var globeImageView: UIImageView = {
        let configuration = UIImage.SymbolConfiguration(pointSize: 36, weight: .regular)
        let imageView = UIImageView(image: UIImage(systemName: "globe", withConfiguration: configuration))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .center
        // No explicit tintColor: the globe inherits the app accent from the
        // view hierarchy's `tintColor`.
        return imageView
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 22, weight: .heavy)
        label.textColor = .label
        label.textAlignment = .center
        label.numberOfLines = 0
        label.text = String(
            format: NSLocalizedString(
                "Browse %@",
                comment: "Anonymous-browse confirmation title, %@ is the instance host"
            ),
            hostname
        )
        return label
    }()

    private lazy var bodyLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.text = String(
            format: NSLocalizedString(
                "You'll see exactly what %@ federates — which can differ from another server's view. It's read-only: voting, commenting and subscribing need an account.",
                comment: "Anonymous-browse confirmation body, %@ is the instance host"
            ),
            hostname
        )
        return label
    }()

    /// The "Reading from <host> · anonymous" pill with a leading eye glyph.
    private lazy var anonymousChip: UIView = {
        let chip = UIView()
        chip.translatesAutoresizingMaskIntoConstraints = false
        chip.backgroundColor = .secondarySystemBackground
        chip.layer.cornerRadius = 12
        chip.layer.cornerCurve = .continuous
        return chip
    }()

    private lazy var chipImageView: UIImageView = {
        let configuration = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        let imageView = UIImageView(image: UIImage(systemName: "eye", withConfiguration: configuration))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .center
        imageView.tintColor = .secondaryLabel
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        return imageView
    }()

    private lazy var chipLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13.5, weight: .semibold)
        label.textColor = .label
        label.text = String(
            format: NSLocalizedString(
                "Reading from %@ · anonymous",
                comment: "Anonymous-browse confirmation chip, %@ is the instance host"
            ),
            hostname
        )
        return label
    }()

    private lazy var startBrowsingButton: OnboardingPrimaryButton = {
        let button = OnboardingPrimaryButton(
            title: NSLocalizedString("Start browsing", comment: "Anonymous-browse primary CTA")
        )
        button.addTarget(self, action: #selector(startBrowsingTapped), for: .touchUpInside)
        return button
    }()

    /// The design's `GhostBtn`: a 44pt borderless, tintColor-text button.
    private lazy var pickServerButton: OnboardingGhostButton = {
        let button = OnboardingGhostButton(
            title: NSLocalizedString("Pick a different server", comment: "Anonymous-browse secondary action")
        )
        button.addTarget(self, action: #selector(pickServerTapped), for: .touchUpInside)
        return button
    }()

    // MARK: Functions

    init(
        instance: InstanceActorId,
        hostname: String,
        dependencies: Dependencies
    ) {
        self.instance = instance
        self.hostname = hostname
        self.dependencies = dependencies

        super.init(nibName: nil, bundle: nil)

        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        navigationItem.title = NSLocalizedString("Browse", comment: "Anonymous-browse screen title")

        view.backgroundColor = Theme.background

        globeTile.addSubview(globeImageView)

        anonymousChip.addSubview(chipImageView)
        anonymousChip.addSubview(chipLabel)

        // Centred column near the top: tile, title, body.
        let headerStackView = UIStackView(arrangedSubviews: [globeTile, titleLabel, bodyLabel])
        headerStackView.translatesAutoresizingMaskIntoConstraints = false
        headerStackView.axis = .vertical
        headerStackView.alignment = .center
        headerStackView.spacing = 9
        headerStackView.setCustomSpacing(16, after: globeTile)

        // Pinned-bottom actions.
        let actionsStackView = UIStackView(arrangedSubviews: [startBrowsingButton, pickServerButton])
        actionsStackView.translatesAutoresizingMaskIntoConstraints = false
        actionsStackView.axis = .vertical
        actionsStackView.alignment = .fill
        actionsStackView.spacing = 4

        view.addSubview(headerStackView)
        view.addSubview(anonymousChip)
        view.addSubview(actionsStackView)

        NSLayoutConstraint.activate([
            globeTile.widthAnchor.constraint(equalToConstant: 76),
            globeTile.heightAnchor.constraint(equalToConstant: 76),
            globeImageView.centerXAnchor.constraint(equalTo: globeTile.centerXAnchor),
            globeImageView.centerYAnchor.constraint(equalTo: globeTile.centerYAnchor),

            headerStackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 34),
            headerStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            headerStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),

            anonymousChip.topAnchor.constraint(equalTo: headerStackView.bottomAnchor, constant: 20),
            anonymousChip.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            anonymousChip.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            chipImageView.leadingAnchor.constraint(equalTo: anonymousChip.leadingAnchor, constant: 13),
            chipImageView.centerYAnchor.constraint(equalTo: anonymousChip.centerYAnchor),

            chipLabel.leadingAnchor.constraint(equalTo: chipImageView.trailingAnchor, constant: 9),
            chipLabel.trailingAnchor.constraint(lessThanOrEqualTo: anonymousChip.trailingAnchor, constant: -13),
            chipLabel.topAnchor.constraint(equalTo: anonymousChip.topAnchor, constant: 11),
            chipLabel.bottomAnchor.constraint(equalTo: anonymousChip.bottomAnchor, constant: -11),

            actionsStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            actionsStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            actionsStackView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -40),
        ])
    }

    // MARK: Actions

    @objc
    private func startBrowsingTapped() {
        accountService.signInAsSignedOut(atInstance: instance)
        dismiss(animated: true)
    }

    @objc
    private func pickServerTapped() {
        navigationController?.popViewController(animated: true)
    }
}
