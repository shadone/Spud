//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import Foundation
import UIKit

class LoginViewController: UIViewController {
    typealias Dependencies =
    HasDataStore &
    HasAccountService &
    HasImageService
    let dependencies: Dependencies

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

        [
            iconImageView,
            instanceNameHorizontalStackView,
            usernameTextField,
            passwordTextField,
            totp2faTokenTextField,
            loginButton,
            forgotPasswordButton,
            registerVerticalStackView,
        ].forEach(stackView.addArrangedSubview)

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

        [
            instanceNameLabel,
            instanceInfoButton,
        ].forEach(stackView.addArrangedSubview)

        return stackView
    }()

    lazy var instanceNameLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "instancename.com"
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

        [
            dontHaveAccountLabel,
            registerButton,
            orLabel,
            anonymousButton,
        ].forEach(stackView.addArrangedSubview)

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

    let viewModel: LoginViewModelType
    var disposables = Set<AnyCancellable>()

    var usernameChangedObserver: NSObjectProtocol?
    var passwordChangedObserver: NSObjectProtocol?

    // MARK: Functions

    init(
        site: LemmySite,
        dependencies: Dependencies
    ) {
        self.dependencies = dependencies

        viewModel = LoginViewModel(
            site: site,
            imageService: dependencies.imageService,
            accountService: dependencies.accountService
        )

        super.init(nibName: nil, bundle: nil)

        setup()
        bindViewModel()
    }

    deinit {
        if let usernameChangedObserver {
            NotificationCenter.default.removeObserver(usernameChangedObserver)
            self.usernameChangedObserver = nil
        }

        if let passwordChangedObserver {
            NotificationCenter.default.removeObserver(passwordChangedObserver)
            self.passwordChangedObserver = nil
        }
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

        usernameChangedObserver = NotificationCenter.default.addObserver(
            forName: UITextField.textDidChangeNotification,
            object: usernameTextField,
            queue: .main) { [weak self] _ in
                self?.usernameChanged()
            }
        passwordChangedObserver = NotificationCenter.default.addObserver(
            forName: UITextField.textDidChangeNotification,
            object: passwordTextField,
            queue: .main) { [weak self] _ in
                self?.passwordChanged()
            }
    }

    private func bindViewModel() {
        viewModel.outputs.icon
            .wrapInOptional()
            .assign(to: \.image, on: iconImageView)
            .store(in: &disposables)

        viewModel.outputs.loginButtonEnabled
            .assign(to: \.isEnabled, on: loginButton)
            .store(in: &disposables)
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func continueWithSignedOutAccount() {
        let account = dependencies.accountService.accountForSignedOut(
            at: viewModel.outputs.site.value,
            isServiceAccount: false,
            in: dependencies.dataStore.mainContext
        )

        dependencies.accountService.setDefaultAccount(account)

        dismiss(animated: true)
    }

    private func usernameChanged() {
        viewModel.inputs.usernameChanged(usernameTextField.text ?? "")
    }

    private func passwordChanged() {
        viewModel.inputs.passwordChanged(passwordTextField.text ?? "")
    }

    @objc private func login() {
        viewModel.inputs.login()
    }
}
