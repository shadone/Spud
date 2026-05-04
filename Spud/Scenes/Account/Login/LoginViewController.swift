//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import UIKit

class LoginViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService
    typealias NestedDependencies =
        LoginViewModel.Dependencies
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    var accountService: AccountServiceType {
        dependencies.own.accountService
    }

    // MARK: UI Properties

    lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()

    lazy var contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    lazy var mainVerticalStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 8

        let subviews = [
            iconImageView,
            instanceNameHorizontalStackView,
            usernameTextField,
            passwordTextField,
            totp2faTokenTextField,
            loginButton,
            forgotPasswordButton,
            registerVerticalStackView,
        ]
        for view in subviews {
            stackView.addArrangedSubview(view)
        }

        stackView.setCustomSpacing(0, after: iconImageView)
        stackView.setCustomSpacing(100, after: forgotPasswordButton)

        return stackView
    }()

    lazy var iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.layer.cornerRadius = 32
        imageView.clipsToBounds = true
        return imageView
    }()

    lazy var instanceNameHorizontalStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal

        let subviews = [
            instanceNameLabel,
            instanceInfoButton,
        ]
        for view in subviews {
            stackView.addArrangedSubview(view)
        }

        return stackView
    }()

    lazy var instanceNameLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    lazy var instanceInfoButton: UIButton = {
        var config = UIButton.Configuration.borderless()
        config.image = UIImage(systemName: "info.circle")!

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false

        return button
    }()

    lazy var usernameTextField: UITextField = {
        let textField = UITextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholder = "Your Email or Username"
        textField.borderStyle = .roundedRect
        textField.keyboardType = .emailAddress
        textField.textContentType = .emailAddress
        textField.autocapitalizationType = .none
        return textField
    }()

    lazy var passwordTextField: UITextField = {
        let textField = UITextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholder = "Password"
        textField.borderStyle = .roundedRect
        textField.isSecureTextEntry = true
        return textField
    }()

    lazy var totp2faTokenTextField: UITextField = {
        let textField = UITextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholder = "One Time Code"
        textField.borderStyle = .roundedRect
        textField.keyboardType = .numberPad
        textField.isHidden = true
        return textField
    }()

    lazy var loginButton: UIButton = {
        var config = UIButton.Configuration.tinted()
        config.title = "Login"

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false

        button.addTarget(self, action: #selector(login), for: .touchUpInside)

        return button
    }()

    lazy var forgotPasswordButton: UIButton = {
        var config = UIButton.Configuration.borderless()
        config.title = "Forgot Password?"

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = .secondaryLabel

        return button
    }()

    lazy var registerVerticalStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .center

        let subviews = [
            dontHaveAccountLabel,
            registerButton,
            orLabel,
            anonymousButton,
        ]
        for view in subviews {
            stackView.addArrangedSubview(view)
        }

        return stackView
    }()

    lazy var dontHaveAccountLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Don't have an account yet?"
        return label
    }()

    lazy var anonymousButton: UIButton = {
        var config = UIButton.Configuration.borderless()
        config.title = "Browse without an account"

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false

        button.addTarget(
            self,
            action: #selector(continueWithSignedOutAccount),
            for: .touchUpInside
        )

        return button
    }()

    lazy var orLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "or"
        return label
    }()

    lazy var registerButton: UIButton = {
        var config = UIButton.Configuration.borderless()
        config.title = "Register"

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false

        return button
    }()

    // MARK: Private

    private let viewModel: LoginViewModel
    private var observationTasks: [Task<Void, Never>] = []

    // MARK: Functions

    init(
        row: SiteListRow,
        dependencies: Dependencies
    ) {
        self.dependencies = (own: dependencies, nested: dependencies)

        viewModel = LoginViewModel(
            row: row,
            dependencies: self.dependencies.nested
        )

        super.init(nibName: nil, bundle: nil)

        setup()
        bindViewModel()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        let cancelBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        navigationItem.leftBarButtonItem = cancelBarButtonItem

        view.backgroundColor = .white

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(mainVerticalStackView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor),

            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),

            mainVerticalStackView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            mainVerticalStackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            mainVerticalStackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, multiplier: 0.8),
            mainVerticalStackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            mainVerticalStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            iconImageView.widthAnchor.constraint(equalToConstant: 64),
            iconImageView.heightAnchor.constraint(equalToConstant: 64),

            usernameTextField.widthAnchor.constraint(equalTo: mainVerticalStackView.widthAnchor),
            passwordTextField.widthAnchor.constraint(equalTo: usernameTextField.widthAnchor),
            loginButton.widthAnchor.constraint(equalTo: usernameTextField.widthAnchor),
            forgotPasswordButton.widthAnchor.constraint(equalTo: usernameTextField.widthAnchor),
            totp2faTokenTextField.widthAnchor.constraint(equalTo: usernameTextField.widthAnchor),
        ])

        usernameTextField.addTarget(self, action: #selector(usernameChanged), for: .editingChanged)
        passwordTextField.addTarget(self, action: #selector(passwordChanged), for: .editingChanged)
    }

    private func bindViewModel() {
        instanceNameLabel.text = viewModel.instanceName

        observationTasks.append(Task { @MainActor [weak self, viewModel] in
            for await image in ObservationStream.values(of: { viewModel.icon }) {
                self?.iconImageView.image = image
            }
        })

        observationTasks.append(Task { @MainActor [weak self, viewModel] in
            for await enabled in ObservationStream.values(of: { viewModel.loginButtonEnabled }) {
                self?.loginButton.isEnabled = enabled
            }
        })

        observationTasks.append(Task { @MainActor [weak self, viewModel] in
            for await loggedIn in ObservationStream.values(of: { viewModel.loggedIn }) {
                guard loggedIn else { continue }
                self?.dismissAfterLogin()
                return
            }
        })
    }

    deinit {
        for task in observationTasks {
            task.cancel()
        }
    }

    private func dismissAfterLogin() {
        dismiss(animated: true)
    }

    @objc
    private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc
    private func continueWithSignedOutAccount() {
        accountService.signInAsSignedOut(atInstance: viewModel.row.instance)
        dismiss(animated: true)
    }

    @objc
    private func usernameChanged() {
        viewModel.username = usernameTextField.text ?? ""
    }

    @objc
    private func passwordChanged() {
        viewModel.password = passwordTextField.text ?? ""
    }

    @objc
    private func login() {
        Task { @MainActor in
            await viewModel.login()
        }
    }
}
