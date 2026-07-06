//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import SpudUIKit
import UIKit

/// The Create-account form. The instance is already chosen by the time we get
/// here (pushed from the login screen's "Create an account"), so this collects
/// username, email, password (+ verify), and - when the instance requires an
/// application - an answer, then calls `RegisterViewModel.register()`.
///
/// Matches the Spud Design `CreateAccount` mockup: a "Create your account"
/// title, a "Home <host>" chip, an accent note box + "Why would you like to
/// join?" answer field (shown only when an application is required), the
/// username / email / password fields, a "Submit application" / "Create account"
/// primary CTA, and an "Already have an account? Log in" line.
///
/// Outcomes: a logged-in registration dismisses the flow; a pending /
/// verify-email outcome pushes `PendingReviewViewController`; a rejection /
/// failure is shown in an alert.
class RegisterViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService
    typealias NestedDependencies =
        PendingReviewViewController.Dependencies
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    // MARK: UI

    private lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive
        scrollView.alwaysBounceVertical = true
        return scrollView
    }()

    private lazy var contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// "Create your account" - ~23pt/800.
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 23, weight: .heavy)
        label.textColor = .label
        label.numberOfLines = 0
        label.text = NSLocalizedString("Create your account", comment: "Create-account screen title")
        return label
    }()

    /// "Home <host>" chip: a `.secondarySystemBackground` pill with a leading
    /// house glyph, a "Home" label, the host, and a trailing chevron. The chevron
    /// is inert (there is no change-instance flow from here).
    private lazy var homeChip: UIView = {
        let chip = UIView()
        chip.translatesAutoresizingMaskIntoConstraints = false
        chip.backgroundColor = .secondarySystemBackground
        chip.layer.cornerRadius = 18
        chip.layer.cornerCurve = .continuous
        return chip
    }()

    private lazy var homeIconImageView: UIImageView = {
        let configuration = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        let imageView = UIImageView(image: UIImage(systemName: "house", withConfiguration: configuration))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .center
        // No explicit tintColor: the house inherits the app accent.
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        return imageView
    }()

    private lazy var homeLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .label
        label.text = NSLocalizedString("Home", comment: "Create-account home chip leading label")
        return label
    }()

    private lazy var homeHostLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        label.text = viewModel.instanceName
        return label
    }()

    private lazy var homeChevronImageView: UIImageView = {
        let configuration = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        let imageView = UIImageView(image: UIImage(systemName: "chevron.down", withConfiguration: configuration))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .center
        imageView.tintColor = .tertiaryLabel
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        return imageView
    }()

    /// Accent-tinted note shown only when an application is required: an eye
    /// glyph plus copy explaining the instance reviews new accounts.
    private lazy var applicationNote: UIView = {
        let note = UIView()
        note.translatesAutoresizingMaskIntoConstraints = false
        note.layer.cornerRadius = 12
        note.layer.cornerCurve = .continuous
        note.layer.borderWidth = 1
        return note
    }()

    private lazy var applicationNoteImageView: UIImageView = {
        let configuration = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        let imageView = UIImageView(image: UIImage(systemName: "eye", withConfiguration: configuration))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .center
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        return imageView
    }()

    private lazy var applicationNoteLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12.5)
        label.textColor = .label
        label.numberOfLines = 0
        label.text = String(
            format: NSLocalizedString(
                "%@ reviews new accounts to keep out spam. Add a line below - you can browse while you wait.",
                comment: "Create-account application note, %@ is the instance host"
            ),
            viewModel.instanceName
        )
        return label
    }()

    private lazy var usernameField: OnboardingLabeledField = {
        let field = OnboardingLabeledField(
            caption: NSLocalizedString("Username", comment: "Create-account username field caption")
        )
        field.textField.textContentType = .username
        field.textField.autocapitalizationType = .none
        field.textField.autocorrectionType = .no
        field.textField.addTarget(self, action: #selector(textChanged), for: .editingChanged)
        return field
    }()

    private lazy var emailField: OnboardingLabeledField = {
        let field = OnboardingLabeledField(
            caption: NSLocalizedString("Email", comment: "Create-account email field caption")
        )
        field.textField.keyboardType = .emailAddress
        field.textField.textContentType = .emailAddress
        field.textField.autocapitalizationType = .none
        field.textField.autocorrectionType = .no
        field.textField.addTarget(self, action: #selector(textChanged), for: .editingChanged)
        return field
    }()

    private lazy var passwordField: OnboardingLabeledField = {
        let field = OnboardingLabeledField(
            caption: NSLocalizedString("Password", comment: "Create-account password field caption"),
            isSecure: true
        )
        field.textField.textContentType = .newPassword
        field.textField.addTarget(self, action: #selector(textChanged), for: .editingChanged)
        return field
    }()

    private lazy var passwordVerifyField: OnboardingLabeledField = {
        let field = OnboardingLabeledField(
            caption: NSLocalizedString("Confirm password", comment: "Create-account confirm-password field caption"),
            isSecure: true
        )
        field.textField.textContentType = .newPassword
        field.textField.addTarget(self, action: #selector(textChanged), for: .editingChanged)
        return field
    }()

    /// The application answer: a caption row ("Why would you like to join?" with
    /// a trailing "Required by <host>" hint) above a multiline text view. Shown
    /// only when an application is required.
    private lazy var answerContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var answerCaptionLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabel
        label.text = NSLocalizedString("Why would you like to join?", comment: "Create-account application answer caption")
        return label
    }()

    private lazy var answerHintLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 11)
        label.textColor = .tertiaryLabel
        label.textAlignment = .right
        label.text = String(
            format: NSLocalizedString(
                "Required by %@",
                comment: "Create-account application answer hint, %@ is the instance host"
            ),
            viewModel.instanceName
        )
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }()

    private lazy var answerTextView: UITextView = {
        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = .secondarySystemBackground
        textView.layer.cornerRadius = 12
        textView.layer.cornerCurve = .continuous
        textView.layer.borderWidth = 1
        textView.layer.borderColor = UIColor.separator.cgColor
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = .label
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 9, bottom: 10, right: 9)
        textView.autocapitalizationType = .sentences
        textView.isScrollEnabled = false
        textView.delegate = self
        return textView
    }()

    private lazy var submitButton: OnboardingPrimaryButton = {
        let button = OnboardingPrimaryButton(title: viewModel.submitButtonTitle)
        button.addTarget(self, action: #selector(submit), for: .touchUpInside)
        return button
    }()

    private lazy var spinner: UIActivityIndicatorView = {
        let view = UIActivityIndicatorView(style: .medium)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.hidesWhenStopped = true
        return view
    }()

    /// "Already have an account? Log in" - the "Log in" clause is accented and
    /// tappable, popping back to the login screen.
    private lazy var loginPromptButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(logInTapped), for: .touchUpInside)
        return button
    }()

    private lazy var contentStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 10
        return stackView
    }()

    // MARK: Private

    private let viewModel: RegisterViewModel
    private var observationTasks: [Task<Void, Never>] = []

    // MARK: Functions

    init(
        row: SiteListRow,
        dependencies: Dependencies
    ) {
        self.dependencies = (own: dependencies, nested: dependencies)
        viewModel = RegisterViewModel(
            row: row,
            accountService: dependencies.accountService
        )

        super.init(nibName: nil, bundle: nil)

        setup()
        bindViewModel()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        for task in observationTasks {
            task.cancel()
        }
    }

    private func setup() {
        view.backgroundColor = Theme.background
        navigationItem.title = NSLocalizedString("Sign up", comment: "Create-account nav title")

        homeChip.addSubview(homeIconImageView)
        homeChip.addSubview(homeLabel)
        homeChip.addSubview(homeHostLabel)
        homeChip.addSubview(homeChevronImageView)

        applicationNote.addSubview(applicationNoteImageView)
        applicationNote.addSubview(applicationNoteLabel)

        // The chip sits in a leading-aligned row so it hugs its content rather
        // than stretching to the full form width.
        let chipRow = UIStackView(arrangedSubviews: [homeChip, UIView()])
        chipRow.axis = .horizontal
        chipRow.alignment = .center

        let answerCaptionRow = UIStackView(arrangedSubviews: [answerCaptionLabel, answerHintLabel])
        answerCaptionRow.translatesAutoresizingMaskIntoConstraints = false
        answerCaptionRow.axis = .horizontal
        answerCaptionRow.alignment = .firstBaseline
        answerCaptionRow.spacing = 8

        answerContainer.addSubview(answerCaptionRow)
        answerContainer.addSubview(answerTextView)

        contentStackView.addArrangedSubview(titleLabel)
        contentStackView.addArrangedSubview(chipRow)
        contentStackView.addArrangedSubview(applicationNote)
        contentStackView.addArrangedSubview(usernameField)
        contentStackView.addArrangedSubview(emailField)
        contentStackView.addArrangedSubview(passwordField)
        contentStackView.addArrangedSubview(passwordVerifyField)
        contentStackView.addArrangedSubview(answerContainer)
        contentStackView.addArrangedSubview(submitButton)
        contentStackView.addArrangedSubview(spinner)
        contentStackView.addArrangedSubview(loginPromptButton)

        contentStackView.setCustomSpacing(12, after: titleLabel)
        contentStackView.setCustomSpacing(12, after: chipRow)
        contentStackView.setCustomSpacing(13, after: applicationNote)
        contentStackView.setCustomSpacing(14, after: passwordVerifyField)
        contentStackView.setCustomSpacing(14, after: answerContainer)
        contentStackView.setCustomSpacing(12, after: submitButton)
        contentStackView.setCustomSpacing(12, after: spinner)

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(contentStackView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),

            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            contentStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 22),
            contentStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -22),
            contentStackView.topAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.topAnchor, constant: 18),
            contentStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24),

            submitButton.heightAnchor.constraint(equalToConstant: 52),

            homeIconImageView.leadingAnchor.constraint(equalTo: homeChip.leadingAnchor, constant: 12),
            homeIconImageView.centerYAnchor.constraint(equalTo: homeChip.centerYAnchor),
            homeLabel.leadingAnchor.constraint(equalTo: homeIconImageView.trailingAnchor, constant: 7),
            homeLabel.centerYAnchor.constraint(equalTo: homeChip.centerYAnchor),
            homeHostLabel.leadingAnchor.constraint(equalTo: homeLabel.trailingAnchor, constant: 5),
            homeHostLabel.centerYAnchor.constraint(equalTo: homeChip.centerYAnchor),
            homeChevronImageView.leadingAnchor.constraint(equalTo: homeHostLabel.trailingAnchor, constant: 6),
            homeChevronImageView.trailingAnchor.constraint(equalTo: homeChip.trailingAnchor, constant: -12),
            homeChevronImageView.centerYAnchor.constraint(equalTo: homeChip.centerYAnchor),
            homeChip.topAnchor.constraint(equalTo: homeChip.superview!.topAnchor),
            homeChip.bottomAnchor.constraint(equalTo: homeChip.superview!.bottomAnchor),
            homeChip.heightAnchor.constraint(equalToConstant: 36),

            applicationNoteImageView.leadingAnchor.constraint(equalTo: applicationNote.leadingAnchor, constant: 12),
            applicationNoteImageView.topAnchor.constraint(equalTo: applicationNote.topAnchor, constant: 11),
            applicationNoteLabel.leadingAnchor.constraint(equalTo: applicationNoteImageView.trailingAnchor, constant: 9),
            applicationNoteLabel.trailingAnchor.constraint(equalTo: applicationNote.trailingAnchor, constant: -12),
            applicationNoteLabel.topAnchor.constraint(equalTo: applicationNote.topAnchor, constant: 10),
            applicationNoteLabel.bottomAnchor.constraint(equalTo: applicationNote.bottomAnchor, constant: -10),

            answerCaptionRow.leadingAnchor.constraint(equalTo: answerContainer.leadingAnchor, constant: 2),
            answerCaptionRow.trailingAnchor.constraint(equalTo: answerContainer.trailingAnchor, constant: -2),
            answerCaptionRow.topAnchor.constraint(equalTo: answerContainer.topAnchor),
            answerTextView.leadingAnchor.constraint(equalTo: answerContainer.leadingAnchor),
            answerTextView.trailingAnchor.constraint(equalTo: answerContainer.trailingAnchor),
            answerTextView.topAnchor.constraint(equalTo: answerCaptionRow.bottomAnchor, constant: 5),
            answerTextView.bottomAnchor.constraint(equalTo: answerContainer.bottomAnchor),
            answerTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 64),
        ])

        updateLoginPromptTitle()
        updateApplicationVisibility()
    }

    /// Shows / hides the application-only views (note box + answer field) to
    /// match `viewModel.requiresApplication`, and refreshes the CTA title.
    private func updateApplicationVisibility() {
        let required = viewModel.requiresApplication
        applicationNote.isHidden = !required
        answerContainer.isHidden = !required
        submitButton.onboardingTitle = viewModel.submitButtonTitle
    }

    private func bindViewModel() {
        observationTasks.append(Task { @MainActor [weak self, viewModel] in
            for await enabled in ObservationStream.values(of: { viewModel.submitEnabled }) {
                self?.submitButton.isEnabled = enabled
            }
        })

        observationTasks.append(Task { @MainActor [weak self, viewModel] in
            for await requires in ObservationStream.values(of: { viewModel.requiresApplication }) {
                _ = requires
                self?.updateApplicationVisibility()
            }
        })

        observationTasks.append(Task { @MainActor [weak self, viewModel] in
            for await submitting in ObservationStream.values(of: { viewModel.isSubmitting }) {
                if submitting {
                    self?.spinner.startAnimating()
                } else {
                    self?.spinner.stopAnimating()
                }
            }
        })

        observationTasks.append(Task { @MainActor [weak self, viewModel] in
            for await loggedIn in ObservationStream.values(of: { viewModel.loggedIn }) {
                guard loggedIn else { continue }
                Haptics.success()
                self?.dismiss(animated: true)
                return
            }
        })

        observationTasks.append(Task { @MainActor [weak self, viewModel] in
            for await outcome in ObservationStream.values(of: { viewModel.pendingOutcome }) {
                guard let outcome else { continue }
                self?.presentPending(outcome)
            }
        })

        observationTasks.append(Task { @MainActor [weak self, viewModel] in
            for await message in ObservationStream.values(of: { viewModel.outcomeMessage }) {
                guard let message else { continue }
                self?.presentOutcome(message)
            }
        })

        observationTasks.append(Task { @MainActor [weak self, viewModel] in
            for await blocked in ObservationStream.values(of: { viewModel.blockedPlatform }) {
                guard let self, let blocked else { continue }
                presentPlatformBlockedSheet(blocked)
            }
        })
    }

    /// Pushes the Pending-review screen for a successful-but-pending outcome. The
    /// account is not yet usable, so we hand the user the status screen (which
    /// also offers "Browse while you wait" via a signed-out sign-in).
    private func presentPending(_ outcome: RegisterViewModel.PendingOutcome) {
        Haptics.success()
        viewModel.pendingOutcome = nil

        let emailEntered = viewModel.email.trimmingCharacters(in: .whitespacesAndNewlines)
        let pending = PendingReviewViewController(
            hostname: viewModel.instanceName,
            instance: viewModel.row.instance,
            email: emailEntered.isEmpty ? nil : emailEntered,
            emailConfirmationNeeded: outcome == .verifyEmail,
            dependencies: dependencies.nested
        )
        navigationController?.pushViewController(pending, animated: true)
    }

    private func presentOutcome(_ message: String) {
        Haptics.warning()
        let alert = UIAlertController(
            title: NSLocalizedString("Sign up", comment: "Create-account outcome alert title"),
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("OK", comment: "OK button"),
            style: .default
        ) { [weak self] _ in
            self?.viewModel.outcomeMessage = nil
        })
        present(alert, animated: true)
    }

    private func updateLoginPromptTitle() {
        let prompt = NSLocalizedString("Already have an account? ", comment: "Create-account login prompt")
        let action = NSLocalizedString("Log in", comment: "Create-account login CTA")

        let string = NSMutableAttributedString(
            string: prompt,
            attributes: [
                .font: UIFont.systemFont(ofSize: 13),
                .foregroundColor: UIColor.secondaryLabel,
            ]
        )
        string.append(NSAttributedString(
            string: action,
            attributes: [
                .font: UIFont.systemFont(ofSize: 13, weight: .bold),
                .foregroundColor: view.tintColor ?? .systemBlue,
            ]
        ))
        loginPromptButton.setAttributedTitle(string, for: .normal)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateLoginPromptTitle()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        // Refresh the accent-driven chrome so it tracks `tintColor` changes
        // (UIViewController has no tintColorDidChange hook).
        updateLoginPromptTitle()
        applyTintColors()
    }

    /// Applies the accent-tinted fill + border on the application note box so it
    /// tracks `tintColor` (and light/dark) changes.
    private func applyTintColors() {
        let accent = view.tintColor ?? .systemBlue
        applicationNote.backgroundColor = accent.withAlphaComponent(0.08)
        applicationNote.layer.borderColor = accent.withAlphaComponent(0.2).cgColor
    }

    // MARK: Actions

    @objc
    private func textChanged() {
        viewModel.username = usernameField.textField.text ?? ""
        viewModel.email = emailField.textField.text ?? ""
        viewModel.password = passwordField.textField.text ?? ""
        viewModel.passwordVerify = passwordVerifyField.textField.text ?? ""
    }

    @objc
    private func submit() {
        Haptics.tap()
        view.endEditing(true)
        Task { @MainActor in
            await viewModel.register()
        }
    }

    @objc
    private func logInTapped() {
        navigationController?.popViewController(animated: true)
    }

    #if DEBUG
    /// Test-only: forces the application-required variant so snapshot references
    /// can render the note box, answer field, and "Submit application" CTA. The
    /// answer field is pre-filled with sample copy mirroring the design mockup.
    func setApplicationStateForTesting(answer: String) {
        viewModel.setRequiresApplicationForTesting(true)
        viewModel.applicationAnswer = answer
        answerTextView.text = answer
        updateApplicationVisibility()
    }
    #endif
}

extension RegisterViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        viewModel.applicationAnswer = textView.text ?? ""
    }
}
