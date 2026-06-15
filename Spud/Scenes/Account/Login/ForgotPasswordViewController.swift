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

/// Password-reset request screen for a chosen instance. Pushed from the login
/// screen's "Forgot password?" affordance. Matches the Spud Design
/// `ForgotPassword` mockup: a "Reset your password" title, an explanatory body
/// naming the instance host, an email field, a "Send reset link" primary CTA,
/// and an info note explaining that resets are handled by the server.
final class ForgotPasswordViewController: UIViewController {
    typealias Dependencies = HasAccountService
    private let dependencies: Dependencies

    private var accountService: AccountServiceType {
        dependencies.accountService
    }

    private let hostname: String
    private let instance: InstanceActorId

    // MARK: UI Properties

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 22, weight: .heavy)
        label.textColor = .label
        label.numberOfLines = 0
        label.text = NSLocalizedString(
            "Reset your password",
            comment: "Forgot-password screen title"
        )
        return label
    }()

    private lazy var bodyLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.text = String(
            format: NSLocalizedString(
                "Enter the email for your %@ account and we'll send a reset link.",
                comment: "Forgot-password body, %@ is the instance host"
            ),
            hostname
        )
        return label
    }()

    private lazy var emailField: OnboardingLabeledField = {
        let field = OnboardingLabeledField(
            caption: NSLocalizedString("Email", comment: "Forgot-password email field caption")
        )
        field.textField.keyboardType = .emailAddress
        field.textField.textContentType = .emailAddress
        field.textField.autocapitalizationType = .none
        field.textField.autocorrectionType = .no
        field.textField.returnKeyType = .send
        field.textField.delegate = self
        return field
    }()

    private lazy var sendButton: OnboardingPrimaryButton = {
        let button = OnboardingPrimaryButton(
            title: NSLocalizedString("Send reset link", comment: "Forgot-password primary CTA")
        )
        button.addTarget(self, action: #selector(sendResetLinkTapped), for: .touchUpInside)
        return button
    }()

    /// Info note: a `.secondarySystemBackground` rounded box with a leading
    /// globe glyph and `.secondaryLabel` copy explaining that the server owns
    /// the reset flow.
    private lazy var infoNote: UIView = {
        let note = UIView()
        note.translatesAutoresizingMaskIntoConstraints = false
        note.backgroundColor = .secondarySystemBackground
        note.layer.cornerRadius = 12
        note.layer.cornerCurve = .continuous
        return note
    }()

    private lazy var infoImageView: UIImageView = {
        let configuration = UIImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        let imageView = UIImageView(image: UIImage(systemName: "globe", withConfiguration: configuration))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .center
        imageView.tintColor = .secondaryLabel
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        return imageView
    }()

    private lazy var infoLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12.5)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.text = String(
            format: NSLocalizedString(
                "Resets are handled by your server, %@ - check its spam folder if nothing arrives.",
                comment: "Forgot-password info note, %@ is the instance host"
            ),
            hostname
        )
        return label
    }()

    // MARK: Functions

    init(
        hostname: String,
        instance: InstanceActorId,
        dependencies: Dependencies
    ) {
        self.hostname = hostname
        self.instance = instance
        self.dependencies = dependencies

        super.init(nibName: nil, bundle: nil)

        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        navigationItem.title = NSLocalizedString("Reset", comment: "Forgot-password screen title")

        view.backgroundColor = Theme.background

        infoNote.addSubview(infoImageView)
        infoNote.addSubview(infoLabel)

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            bodyLabel,
            emailField,
            sendButton,
            infoNote,
        ])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 13
        stackView.setCustomSpacing(8, after: titleLabel)
        stackView.setCustomSpacing(20, after: bodyLabel)
        stackView.setCustomSpacing(6, after: emailField)
        stackView.setCustomSpacing(18, after: sendButton)

        view.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),

            sendButton.heightAnchor.constraint(equalToConstant: 52),

            infoImageView.leadingAnchor.constraint(equalTo: infoNote.leadingAnchor, constant: 12),
            infoImageView.topAnchor.constraint(equalTo: infoNote.topAnchor, constant: 13),

            infoLabel.leadingAnchor.constraint(equalTo: infoImageView.trailingAnchor, constant: 9),
            infoLabel.trailingAnchor.constraint(equalTo: infoNote.trailingAnchor, constant: -12),
            infoLabel.topAnchor.constraint(equalTo: infoNote.topAnchor, constant: 12),
            infoLabel.bottomAnchor.constraint(equalTo: infoNote.bottomAnchor, constant: -12),
        ])
    }

    // MARK: Actions

    @objc
    private func sendResetLinkTapped() {
        view.endEditing(true)

        let email = emailField.textField.text ?? ""
        guard !email.isEmpty else {
            emailField.errorText = NSLocalizedString(
                "Enter your email address.",
                comment: "Forgot-password empty-email error"
            )
            return
        }
        emailField.errorText = nil

        sendButton.isEnabled = false
        Task { [weak self] in
            guard let self else { return }
            do {
                try await accountService.passwordReset(atInstance: instance, email: email)
                presentConfirmation()
            } catch {
                sendButton.isEnabled = true
                presentFailure()
            }
        }
    }

    /// Brief success confirmation. The reset email is sent by the server; we tell
    /// the user to check their inbox, then pop back to the login screen.
    private func presentConfirmation() {
        let alert = UIAlertController(
            title: NSLocalizedString("Check your email", comment: "Forgot-password success alert title"),
            message: String(
                format: NSLocalizedString(
                    "If an account exists for %@, a reset link is on its way. Check your spam folder if nothing arrives.",
                    comment: "Forgot-password success alert body, %@ is the email address"
                ),
                emailField.textField.text ?? ""
            ),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("OK", comment: "Forgot-password success alert dismiss"),
            style: .default,
            handler: { [weak self] _ in
                self?.navigationController?.popViewController(animated: true)
            }
        ))
        present(alert, animated: true)
    }

    private func presentFailure() {
        let alert = UIAlertController(
            title: NSLocalizedString("Couldn't send reset link", comment: "Forgot-password failure alert title"),
            message: NSLocalizedString(
                "Something went wrong reaching your server. Please try again.",
                comment: "Forgot-password failure alert body"
            ),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("OK", comment: "Forgot-password failure alert dismiss"),
            style: .default
        ))
        present(alert, animated: true)
    }
}

extension ForgotPasswordViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_: UITextField) -> Bool {
        sendResetLinkTapped()
        return true
    }
}
