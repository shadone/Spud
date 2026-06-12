//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import SpudUIKit
import UIKit

/// The Sign Up form. The instance is already chosen by the time we get here
/// (pushed from the login screen's "Register"), so this collects username,
/// email, password (+ verify), and an optional application answer, then calls
/// `RegisterViewModel.register()`. Pending / verify-email outcomes are shown in
/// an alert; a successful logged-in registration dismisses the flow.
class RegisterViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService
    typealias NestedDependencies =
        HasVoid
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    // MARK: UI

    private lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive
        return scrollView
    }()

    private lazy var contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.boldSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .title1).pointSize)
        label.adjustsFontForContentSizeCategory = true
        label.text = NSLocalizedString("Create account", comment: "Sign up screen title")
        label.numberOfLines = 0
        return label
    }()

    private lazy var instanceLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.text = String(
            format: NSLocalizedString("on %@", comment: "Sign up: which instance, e.g. 'on lemmy.world'"),
            viewModel.instanceName
        )
        return label
    }()

    private lazy var usernameTextField = makeTextField(
        placeholder: NSLocalizedString("Username", comment: "Sign up username field placeholder"),
        contentType: .username
    )

    private lazy var emailTextField: UITextField = {
        let field = makeTextField(
            placeholder: NSLocalizedString("Email (optional)", comment: "Sign up email field placeholder"),
            contentType: .emailAddress
        )
        field.keyboardType = .emailAddress
        return field
    }()

    private lazy var passwordTextField: UITextField = {
        let field = makeTextField(
            placeholder: NSLocalizedString("Password", comment: "Sign up password field placeholder"),
            contentType: .newPassword
        )
        field.isSecureTextEntry = true
        return field
    }()

    private lazy var passwordVerifyTextField: UITextField = {
        let field = makeTextField(
            placeholder: NSLocalizedString("Confirm password", comment: "Sign up confirm-password field placeholder"),
            contentType: .newPassword
        )
        field.isSecureTextEntry = true
        return field
    }()

    private lazy var applicationAnswerTextField = makeTextField(
        placeholder: NSLocalizedString("Why do you want to join? (if required)", comment: "Sign up application answer placeholder"),
        contentType: nil
    )

    private lazy var nsfwRow: UIStackView = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = NSLocalizedString("Show NSFW content", comment: "Sign up NSFW toggle label")
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true

        let row = UIStackView(arrangedSubviews: [label, nsfwSwitch])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.axis = .horizontal
        row.alignment = .center
        return row
    }()

    private lazy var nsfwSwitch: UISwitch = {
        let toggle = UISwitch()
        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.addTarget(self, action: #selector(nsfwChanged), for: .valueChanged)
        return toggle
    }()

    private lazy var submitButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = NSLocalizedString("Sign up", comment: "Sign up submit button")
        config.cornerStyle = .medium
        config.buttonSize = .large
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(submit), for: .touchUpInside)
        return button
    }()

    private lazy var spinner: UIActivityIndicatorView = {
        let view = UIActivityIndicatorView(style: .medium)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.hidesWhenStopped = true
        return view
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
        view.backgroundColor = .systemBackground
        navigationItem.title = NSLocalizedString("Sign up", comment: "Sign up nav title")

        let stack = UIStackView(arrangedSubviews: [
            titleLabel,
            instanceLabel,
            usernameTextField,
            emailTextField,
            passwordTextField,
            passwordVerifyTextField,
            applicationAnswerTextField,
            nsfwRow,
            submitButton,
            spinner,
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 12
        stack.setCustomSpacing(4, after: titleLabel)
        stack.setCustomSpacing(24, after: instanceLabel)
        stack.setCustomSpacing(20, after: nsfwRow)

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(stack)

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

            stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24),
        ])

        usernameTextField.addTarget(self, action: #selector(textChanged), for: .editingChanged)
        emailTextField.addTarget(self, action: #selector(textChanged), for: .editingChanged)
        passwordTextField.addTarget(self, action: #selector(textChanged), for: .editingChanged)
        passwordVerifyTextField.addTarget(self, action: #selector(textChanged), for: .editingChanged)
        applicationAnswerTextField.addTarget(self, action: #selector(textChanged), for: .editingChanged)
    }

    private func bindViewModel() {
        observationTasks.append(Task { @MainActor [weak self, viewModel] in
            for await enabled in ObservationStream.values(of: { viewModel.submitEnabled }) {
                self?.submitButton.isEnabled = enabled
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
            for await message in ObservationStream.values(of: { viewModel.outcomeMessage }) {
                guard let message else { continue }
                self?.presentOutcome(message)
            }
        })
    }

    private func presentOutcome(_ message: String) {
        Haptics.warning()
        let alert = UIAlertController(
            title: NSLocalizedString("Sign up", comment: "Sign up outcome alert title"),
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

    private func makeTextField(placeholder: String, contentType: UITextContentType?) -> UITextField {
        let field = UITextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.placeholder = placeholder
        field.borderStyle = .roundedRect
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.textContentType = contentType
        return field
    }

    // MARK: Actions

    @objc
    private func textChanged() {
        viewModel.username = usernameTextField.text ?? ""
        viewModel.email = emailTextField.text ?? ""
        viewModel.password = passwordTextField.text ?? ""
        viewModel.passwordVerify = passwordVerifyTextField.text ?? ""
        viewModel.applicationAnswer = applicationAnswerTextField.text ?? ""
    }

    @objc
    private func nsfwChanged() {
        viewModel.showNsfw = nsfwSwitch.isOn
    }

    @objc
    private func submit() {
        Haptics.tap()
        view.endEditing(true)
        Task { @MainActor in
            await viewModel.register()
        }
    }
}
