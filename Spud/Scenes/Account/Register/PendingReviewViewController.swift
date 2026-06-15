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

/// Shown after a successful application submit, when the new account is awaiting
/// admin approval (or an email still needs verifying). Matches the Spud Design
/// `Pending` mockup: a centred clock tile, a "You're on the list" title, a body
/// naming the instance, a two-row status checklist card (email + application),
/// and - pinned near the bottom - a "Browse while you wait" primary CTA plus a
/// "Check application status" ghost button.
///
/// "Browse while you wait" signs in as a signed-out account for the instance and
/// dismisses, so MainWindow swaps to the tab bar. "Check application status" is
/// inert: Lemmy exposes no application-status endpoint, so it is a no-op
/// placeholder (TODO: wire when / if such an endpoint exists).
final class PendingReviewViewController: UIViewController {
    typealias Dependencies = HasAccountService
    private let dependencies: Dependencies

    private var accountService: AccountServiceType {
        dependencies.accountService
    }

    private let hostname: String
    private let instance: InstanceActorId
    private let email: String?
    /// Whether the email still needs confirming. When true, the first checklist
    /// row shows a pending "Check your email" state instead of a confirmed one.
    private let emailConfirmationNeeded: Bool

    // MARK: UI Properties

    /// The 84pt circle holding the clock glyph: a low-alpha `tintColor` fill with
    /// a ~1.5pt `tintColor` border. Colors are applied in `applyTintColors()` so
    /// they track `tintColor` changes.
    private lazy var clockTile: UIView = {
        let tile = UIView()
        tile.translatesAutoresizingMaskIntoConstraints = false
        tile.layer.cornerRadius = 42
        tile.layer.borderWidth = 1.5
        return tile
    }()

    private lazy var clockImageView: UIImageView = {
        let configuration = UIImage.SymbolConfiguration(pointSize: 38, weight: .regular)
        let imageView = UIImageView(image: UIImage(systemName: "clock", withConfiguration: configuration))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .center
        // No explicit tintColor: the clock inherits the app accent.
        return imageView
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 26, weight: .heavy)
        label.textColor = .label
        label.textAlignment = .center
        label.numberOfLines = 0
        label.text = NSLocalizedString("You're on the list", comment: "Pending-review screen title")
        return label
    }()

    private lazy var bodyLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14.5)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.text = String(
            format: NSLocalizedString(
                "%@ is reviewing your application. We'll email you the moment you're approved - usually within a day.",
                comment: "Pending-review body, %@ is the instance host"
            ),
            hostname
        )
        return label
    }()

    /// The status checklist card: a `.secondarySystemBackground` rounded box with
    /// an email row and an application row, separated by a hairline.
    private lazy var checklistCard: UIView = {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 14
        card.layer.cornerCurve = .continuous
        card.clipsToBounds = true
        return card
    }()

    private lazy var emailRow: ChecklistRow = {
        if emailConfirmationNeeded {
            return ChecklistRow(
                state: .pending,
                title: NSLocalizedString("Check your email", comment: "Pending-review email row title, not yet confirmed"),
                subtitle: email ?? NSLocalizedString(
                    "Confirm your address to finish",
                    comment: "Pending-review email row subtitle, no email on file"
                ),
                pillText: nil
            )
        }
        return ChecklistRow(
            state: .done,
            title: NSLocalizedString("Email confirmed", comment: "Pending-review email row title, confirmed"),
            subtitle: email ?? NSLocalizedString(
                "No email - approval only",
                comment: "Pending-review email row subtitle, no email on file"
            ),
            pillText: nil
        )
    }()

    private lazy var applicationRow = ChecklistRow(
        state: .pending,
        title: NSLocalizedString("Application under review", comment: "Pending-review application row title"),
        subtitle: NSLocalizedString("A moderator will take a look soon", comment: "Pending-review application row subtitle"),
        pillText: NSLocalizedString("Pending", comment: "Pending-review application row pill")
    )

    private lazy var hairline: UIView = {
        let line = UIView()
        line.translatesAutoresizingMaskIntoConstraints = false
        line.backgroundColor = .separator
        return line
    }()

    private lazy var browseButton: OnboardingPrimaryButton = {
        let button = OnboardingPrimaryButton(
            title: NSLocalizedString("Browse while you wait", comment: "Pending-review primary CTA")
        )
        button.addTarget(self, action: #selector(browseTapped), for: .touchUpInside)
        return button
    }()

    private lazy var statusButton: OnboardingGhostButton = {
        let button = OnboardingGhostButton(
            title: NSLocalizedString("Check application status", comment: "Pending-review secondary action")
        )
        button.addTarget(self, action: #selector(checkStatusTapped), for: .touchUpInside)
        return button
    }()

    // MARK: Functions

    init(
        hostname: String,
        instance: InstanceActorId,
        email: String?,
        emailConfirmationNeeded: Bool,
        dependencies: Dependencies
    ) {
        self.hostname = hostname
        self.instance = instance
        self.email = email
        self.emailConfirmationNeeded = emailConfirmationNeeded
        self.dependencies = dependencies

        super.init(nibName: nil, bundle: nil)

        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        navigationItem.title = NSLocalizedString("Pending", comment: "Pending-review screen title")
        // No back button: the application has been submitted, popping back to the
        // form would be misleading.
        navigationItem.hidesBackButton = true

        view.backgroundColor = Theme.background

        clockTile.addSubview(clockImageView)

        // Centred header column near the top: clock tile, title, body.
        let headerStackView = UIStackView(arrangedSubviews: [clockTile, titleLabel, bodyLabel])
        headerStackView.translatesAutoresizingMaskIntoConstraints = false
        headerStackView.axis = .vertical
        headerStackView.alignment = .center
        headerStackView.spacing = 10
        headerStackView.setCustomSpacing(22, after: clockTile)

        checklistCard.addSubview(emailRow)
        checklistCard.addSubview(hairline)
        checklistCard.addSubview(applicationRow)

        // Pinned-bottom actions.
        let actionsStackView = UIStackView(arrangedSubviews: [browseButton, statusButton])
        actionsStackView.translatesAutoresizingMaskIntoConstraints = false
        actionsStackView.axis = .vertical
        actionsStackView.alignment = .fill
        actionsStackView.spacing = 6

        view.addSubview(headerStackView)
        view.addSubview(checklistCard)
        view.addSubview(actionsStackView)

        NSLayoutConstraint.activate([
            clockTile.widthAnchor.constraint(equalToConstant: 84),
            clockTile.heightAnchor.constraint(equalToConstant: 84),
            clockImageView.centerXAnchor.constraint(equalTo: clockTile.centerXAnchor),
            clockImageView.centerYAnchor.constraint(equalTo: clockTile.centerYAnchor),

            headerStackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40),
            headerStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            headerStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),

            checklistCard.topAnchor.constraint(equalTo: headerStackView.bottomAnchor, constant: 28),
            checklistCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            checklistCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            emailRow.topAnchor.constraint(equalTo: checklistCard.topAnchor),
            emailRow.leadingAnchor.constraint(equalTo: checklistCard.leadingAnchor),
            emailRow.trailingAnchor.constraint(equalTo: checklistCard.trailingAnchor),

            hairline.topAnchor.constraint(equalTo: emailRow.bottomAnchor),
            hairline.leadingAnchor.constraint(equalTo: checklistCard.leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: checklistCard.trailingAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 0.5),

            applicationRow.topAnchor.constraint(equalTo: hairline.bottomAnchor),
            applicationRow.leadingAnchor.constraint(equalTo: checklistCard.leadingAnchor),
            applicationRow.trailingAnchor.constraint(equalTo: checklistCard.trailingAnchor),
            applicationRow.bottomAnchor.constraint(equalTo: checklistCard.bottomAnchor),

            actionsStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            actionsStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            actionsStackView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -38),

            browseButton.heightAnchor.constraint(equalToConstant: 52),
        ])

        applyTintColors()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        // Re-derive the accent-driven clock colors on every layout pass so they
        // track `tintColor` and light/dark changes.
        applyTintColors()
    }

    /// Re-applies the accent-derived colors on the clock tile so they track
    /// `tintColor` (and light/dark) changes.
    private func applyTintColors() {
        let accent = view.tintColor ?? .systemBlue
        clockTile.backgroundColor = accent.withAlphaComponent(0.12)
        clockTile.layer.borderColor = accent.withAlphaComponent(0.27).cgColor
    }

    // MARK: Actions

    @objc
    private func browseTapped() {
        Haptics.tap()
        accountService.signInAsSignedOut(atInstance: instance)
        dismiss(animated: true)
    }

    @objc
    private func checkStatusTapped() {
        // Lemmy exposes no application-status endpoint, so there's nothing to
        // poll. We brief the user to wait for the approval email. (TODO: wire a
        // real status check if / when such an endpoint exists.)
        let alert = UIAlertController(
            title: NSLocalizedString("Still under review", comment: "Pending-review status alert title"),
            message: String(
                format: NSLocalizedString(
                    "%@ hasn't finished reviewing your application yet. We'll email you the moment you're approved.",
                    comment: "Pending-review status alert body, %@ is the instance host"
                ),
                hostname
            ),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("OK", comment: "OK button"),
            style: .default
        ))
        present(alert, animated: true)
    }
}

/// A single status row in the Pending-review checklist: a leading state badge
/// (a filled accent check when done, or a hollow accent ring with a centred dot
/// when pending), a title + subtitle, and an optional trailing "Pending" pill.
/// Matches the design's two checklist rows.
private final class ChecklistRow: UIView {
    enum State {
        case done
        case pending
    }

    private let state: State
    private let pillText: String?

    private let badge = UIView()
    private lazy var badgeCheckImageView: UIImageView = {
        let configuration = UIImage.SymbolConfiguration(pointSize: 13, weight: .heavy)
        let imageView = UIImageView(image: UIImage(systemName: "checkmark", withConfiguration: configuration))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .center
        imageView.tintColor = .white
        return imageView
    }()

    private let badgeDot = UIView()

    private let pillLabel = UILabel()
    private let pillBackground = UIView()

    init(state: State, title: String, subtitle: String, pillText: String?) {
        self.state = state
        self.pillText = pillText
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.layer.cornerRadius = 13

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 14.5, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.text = title
        titleLabel.numberOfLines = 0

        let subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.text = subtitle
        subtitleLabel.numberOfLines = 0

        let textStackView = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStackView.translatesAutoresizingMaskIntoConstraints = false
        textStackView.axis = .vertical
        textStackView.spacing = 1

        addSubview(badge)
        addSubview(textStackView)

        switch state {
        case .done:
            badge.addSubview(badgeCheckImageView)
        case .pending:
            badge.layer.borderWidth = 2
            badgeDot.translatesAutoresizingMaskIntoConstraints = false
            badgeDot.layer.cornerRadius = 4
            badge.addSubview(badgeDot)
        }

        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: 26),
            badge.heightAnchor.constraint(equalToConstant: 26),
            badge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 15),
            badge.centerYAnchor.constraint(equalTo: centerYAnchor),

            textStackView.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 12),
            textStackView.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            textStackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
        ])

        switch state {
        case .done:
            NSLayoutConstraint.activate([
                badgeCheckImageView.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
                badgeCheckImageView.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            ])
        case .pending:
            NSLayoutConstraint.activate([
                badgeDot.widthAnchor.constraint(equalToConstant: 8),
                badgeDot.heightAnchor.constraint(equalToConstant: 8),
                badgeDot.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
                badgeDot.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            ])
        }

        if let pillText {
            pillBackground.translatesAutoresizingMaskIntoConstraints = false
            pillBackground.layer.cornerRadius = 10
            pillBackground.layer.cornerCurve = .continuous

            pillLabel.translatesAutoresizingMaskIntoConstraints = false
            pillLabel.font = .systemFont(ofSize: 12, weight: .bold)
            pillLabel.text = pillText

            pillBackground.addSubview(pillLabel)
            addSubview(pillBackground)

            NSLayoutConstraint.activate([
                pillBackground.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -15),
                pillBackground.centerYAnchor.constraint(equalTo: centerYAnchor),
                pillBackground.leadingAnchor.constraint(greaterThanOrEqualTo: textStackView.trailingAnchor, constant: 8),
                pillLabel.leadingAnchor.constraint(equalTo: pillBackground.leadingAnchor, constant: 9),
                pillLabel.trailingAnchor.constraint(equalTo: pillBackground.trailingAnchor, constant: -9),
                pillLabel.topAnchor.constraint(equalTo: pillBackground.topAnchor, constant: 3),
                pillLabel.bottomAnchor.constraint(equalTo: pillBackground.bottomAnchor, constant: -3),
            ])
        } else {
            textStackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -15).isActive = true
        }

        applyTintColors()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        applyTintColors()
    }

    private func applyTintColors() {
        let accent = tintColor ?? .systemBlue
        switch state {
        case .done:
            badge.backgroundColor = accent
        case .pending:
            badge.backgroundColor = .clear
            badge.layer.borderColor = accent.cgColor
            badgeDot.backgroundColor = accent
        }
        pillLabel.textColor = accent
        pillBackground.backgroundColor = accent.withAlphaComponent(0.11)
    }
}
