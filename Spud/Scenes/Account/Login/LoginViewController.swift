//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import SpudUIKit
import UIKit

/// Login form for a chosen instance. Matches the Spud Design `LoginForm`
/// mockup: an instance header card (gradient banner + avatar + host), the
/// username / password fields, the primary "Log in" CTA, a forgot-password
/// affordance, a "create an account" line, an "or" divider, and an outlined
/// "browse anonymously" row. The 2FA one-time-code field is preserved but
/// stays hidden (it is promoted to its own screen in a later slice).
class LoginViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService
    typealias NestedDependencies =
        LoginViewModel.Dependencies &
        RegisterViewController.Dependencies
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    var accountService: AccountServiceType {
        dependencies.own.accountService
    }

    // MARK: UI Properties

    lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
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
        stackView.alignment = .fill
        stackView.spacing = 13

        let subviews = [
            instanceHeaderCard,
            usernameField,
            passwordField,
            loginButton,
            twoFactorButton,
            forgotPasswordButton,
            registerLineLabel,
            orDividerStackView,
            anonymousButton,
        ]
        for view in subviews {
            stackView.addArrangedSubview(view)
        }

        stackView.setCustomSpacing(18, after: instanceHeaderCard)
        stackView.setCustomSpacing(6, after: passwordField)
        stackView.setCustomSpacing(14, after: loginButton)
        stackView.setCustomSpacing(2, after: twoFactorButton)
        stackView.setCustomSpacing(18, after: forgotPasswordButton)
        stackView.setCustomSpacing(20, after: registerLineLabel)
        stackView.setCustomSpacing(14, after: orDividerStackView)

        return stackView
    }()

    // MARK: Instance header card

    /// Rounded card holding the gradient banner, instance avatar, host name,
    /// "Change" affordance and a blurb line.
    lazy var instanceHeaderCard: UIView = {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 14
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 0.5
        card.layer.borderColor = UIColor.separator.cgColor
        card.clipsToBounds = true
        return card
    }()

    lazy var bannerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let bannerGradient = CAGradientLayer()

    /// The 46pt rounded-square instance avatar with a 3pt background ring,
    /// overlapping the banner bottom. Reuses the observed `viewModel.icon`.
    lazy var iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 12
        imageView.layer.cornerCurve = .continuous
        imageView.layer.borderWidth = 3
        imageView.layer.borderColor = Theme.background.cgColor
        imageView.backgroundColor = .tertiarySystemBackground
        return imageView
    }()

    lazy var instanceNameLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 16, weight: .heavy)
        label.textColor = .label
        return label
    }()

    lazy var changeButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.title = NSLocalizedString("Change", comment: "Change instance affordance on login")
        config.contentInsets = .zero
        config.attributedTitle = AttributedString(
            NSLocalizedString("Change", comment: "Change instance affordance on login"),
            attributes: AttributeContainer([
                .font: UIFont.systemFont(ofSize: 13.5, weight: .semibold),
            ])
        )

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        // No change flow yet; this is an inert visual affordance for now.
        button.isEnabled = false
        return button
    }()

    lazy var blurbLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12.5)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        return label
    }()

    // MARK: Fields

    lazy var usernameField: OnboardingLabeledField = {
        let field = OnboardingLabeledField(
            caption: NSLocalizedString("Username or email", comment: "Login field caption")
        )
        field.textField.keyboardType = .emailAddress
        field.textField.textContentType = .emailAddress
        field.textField.autocapitalizationType = .none
        field.textField.autocorrectionType = .no
        field.textField.returnKeyType = .next
        return field
    }()

    lazy var passwordField: OnboardingLabeledField = {
        let field = OnboardingLabeledField(
            caption: NSLocalizedString("Password", comment: "Login field caption"),
            isSecure: true
        )
        field.textField.textContentType = .password
        field.textField.returnKeyType = .go
        return field
    }()

    /// "Have a two-factor code?" affordance shown beneath the primary CTA. Taps
    /// through to the dedicated `LoginTwoFactorViewController` code-entry screen.
    /// This is the manual entry point; the same screen is also presented
    /// automatically when the server rejects a login with
    /// `AccountServiceLoginError.totp2faRequired`. The collected code is forwarded
    /// to the account-service login path as the `totp2faToken`.
    lazy var twoFactorButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.attributedTitle = AttributedString(
            NSLocalizedString("Have a two-factor code?", comment: "Login two-factor affordance"),
            attributes: AttributeContainer([
                .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
            ])
        )

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(twoFactorTapped), for: .touchUpInside)
        return button
    }()

    lazy var loginButton: OnboardingPrimaryButton = {
        let button = OnboardingPrimaryButton(
            title: NSLocalizedString("Log in", comment: "Login primary CTA")
        )
        button.addTarget(self, action: #selector(login), for: .touchUpInside)
        return button
    }()

    lazy var forgotPasswordButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.attributedTitle = AttributedString(
            NSLocalizedString("Forgot password?", comment: "Login forgot-password affordance"),
            attributes: AttributeContainer([
                .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
            ])
        )

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(forgotPasswordTapped), for: .touchUpInside)
        return button
    }()

    /// "New to Spud? Create an account" — the second clause is the accent and
    /// taps through to `registerTapped()`.
    lazy var registerLineLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isUserInteractionEnabled = true
        label.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(registerTapped))
        )
        return label
    }()

    /// hairline · "or" · hairline divider.
    lazy var orDividerStackView: UIStackView = {
        @MainActor
        func hairline() -> UIView {
            let line = UIView()
            line.translatesAutoresizingMaskIntoConstraints = false
            line.backgroundColor = .separator
            line.heightAnchor.constraint(equalToConstant: 1).isActive = true
            return line
        }

        let leadingHairline = hairline()
        let trailingHairline = hairline()

        let orLabel = UILabel()
        orLabel.translatesAutoresizingMaskIntoConstraints = false
        orLabel.text = NSLocalizedString("or", comment: "Login divider")
        orLabel.font = .systemFont(ofSize: 12)
        orLabel.textColor = .tertiaryLabel
        orLabel.setContentHuggingPriority(.required, for: .horizontal)

        let stackView = UIStackView(arrangedSubviews: [leadingHairline, orLabel, trailingHairline])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .fill
        stackView.spacing = 12

        // Both rules share the leftover width equally around the "or". Activated
        // after the hairlines join the stack so they share a common ancestor.
        leadingHairline.widthAnchor.constraint(equalTo: trailingHairline.widthAnchor).isActive = true
        return stackView
    }()

    /// 50pt outlined "browse anonymously" row with a leading eye glyph.
    lazy var anonymousButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "eye")
        config.imagePadding = 8
        config.baseForegroundColor = .label
        config.background.backgroundColor = .secondarySystemBackground
        config.background.cornerRadius = 14
        config.background.strokeColor = .separator
        config.background.strokeWidth = 1

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = .secondaryLabel
        button.addTarget(
            self,
            action: #selector(browseAnonymouslyTapped),
            for: .touchUpInside
        )
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
        navigationItem.title = NSLocalizedString("Log in", comment: "Login screen title")

        view.backgroundColor = Theme.background

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(mainVerticalStackView)

        layoutInstanceHeaderCard()

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            mainVerticalStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            mainVerticalStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            mainVerticalStackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            mainVerticalStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24),

            loginButton.heightAnchor.constraint(equalToConstant: 52),
            anonymousButton.heightAnchor.constraint(equalToConstant: 50),
        ])

        usernameField.textField.addTarget(self, action: #selector(usernameChanged), for: .editingChanged)
        passwordField.textField.addTarget(self, action: #selector(passwordChanged), for: .editingChanged)

        // Re-resolve the gradient and layer border cgColors when the interface
        // style changes (light/dark). Replaces the deprecated
        // traitCollectionDidChange override with the iOS 17+ registration API.
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _: UITraitCollection) in
            self.applyBannerGradientColors()
            self.instanceHeaderCard.layer.borderColor = UIColor.separator.cgColor
            self.iconImageView.layer.borderColor = Theme.background.cgColor
        }
    }

    private func layoutInstanceHeaderCard() {
        bannerView.layer.insertSublayer(bannerGradient, at: 0)

        instanceHeaderCard.addSubview(bannerView)
        instanceHeaderCard.addSubview(iconImageView)
        instanceHeaderCard.addSubview(instanceNameLabel)
        instanceHeaderCard.addSubview(changeButton)
        instanceHeaderCard.addSubview(blurbLabel)

        NSLayoutConstraint.activate([
            bannerView.leadingAnchor.constraint(equalTo: instanceHeaderCard.leadingAnchor),
            bannerView.trailingAnchor.constraint(equalTo: instanceHeaderCard.trailingAnchor),
            bannerView.topAnchor.constraint(equalTo: instanceHeaderCard.topAnchor),
            bannerView.heightAnchor.constraint(equalToConstant: 58),

            // Avatar overlaps the banner bottom by ~20pt.
            iconImageView.widthAnchor.constraint(equalToConstant: 46),
            iconImageView.heightAnchor.constraint(equalToConstant: 46),
            iconImageView.leadingAnchor.constraint(equalTo: instanceHeaderCard.leadingAnchor, constant: 13),
            iconImageView.topAnchor.constraint(equalTo: bannerView.bottomAnchor, constant: -20),

            instanceNameLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 11),
            instanceNameLabel.bottomAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: -3),

            changeButton.leadingAnchor.constraint(greaterThanOrEqualTo: instanceNameLabel.trailingAnchor, constant: 8),
            changeButton.trailingAnchor.constraint(equalTo: instanceHeaderCard.trailingAnchor, constant: -13),
            changeButton.bottomAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: -4),

            blurbLabel.leadingAnchor.constraint(equalTo: instanceHeaderCard.leadingAnchor, constant: 13),
            blurbLabel.trailingAnchor.constraint(equalTo: instanceHeaderCard.trailingAnchor, constant: -13),
            blurbLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 6),
            blurbLabel.bottomAnchor.constraint(equalTo: instanceHeaderCard.bottomAnchor, constant: -11),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        bannerGradient.frame = bannerView.bounds
        applyBannerGradientColors()
    }

    /// A subtle diagonal gradient derived from the app accent.
    private func applyBannerGradientColors() {
        let accent = view.tintColor ?? .systemBlue
        bannerGradient.startPoint = CGPoint(x: 0, y: 0)
        bannerGradient.endPoint = CGPoint(x: 1, y: 1)
        bannerGradient.colors = [
            accent.withAlphaComponent(0.55).cgColor,
            accent.withAlphaComponent(0.2).cgColor,
        ]
    }

    private func bindViewModel() {
        instanceNameLabel.text = viewModel.instanceName
        applyBannerGradientColors()

        let anonymousTitle = String(
            format: NSLocalizedString(
                "Browse %@ anonymously",
                comment: "Login anonymous-browse row, %@ is the instance host"
            ),
            viewModel.instanceName
        )
        anonymousButton.configuration?.attributedTitle = AttributedString(
            anonymousTitle,
            attributes: AttributeContainer([
                .font: UIFont.systemFont(ofSize: 15.5, weight: .semibold),
            ])
        )

        let blurb = viewModel.row.descriptionText
        if let blurb, !blurb.isEmpty {
            blurbLabel.text = blurb
        } else {
            blurbLabel.text = viewModel.instanceName
        }

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
            for await error in ObservationStream.values(of: { viewModel.loginError }) {
                self?.passwordField.errorText = error
            }
        })

        observationTasks.append(Task { @MainActor [weak self, viewModel] in
            for await loggedIn in ObservationStream.values(of: { viewModel.loggedIn }) {
                guard loggedIn else { continue }
                self?.dismissAfterLogin()
                return
            }
        })

        observationTasks.append(Task { @MainActor [weak self, viewModel] in
            for await needsCode in ObservationStream.values(of: { viewModel.needsTwoFactorCode }) {
                guard needsCode else { continue }
                self?.presentTwoFactorEntry()
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

    /// Pushes the read-only confirmation screen instead of signing in
    /// immediately, giving the user a chance to understand what anonymous
    /// browsing means before committing.
    @objc
    private func browseAnonymouslyTapped() {
        let viewController = AnonymousBrowseConfirmViewController(
            instance: viewModel.row.instance,
            hostname: viewModel.instanceName,
            dependencies: dependencies.own
        )
        navigationController?.pushViewController(viewController, animated: true)
    }

    @objc
    private func usernameChanged() {
        viewModel.username = usernameField.textField.text ?? ""
    }

    @objc
    private func passwordChanged() {
        viewModel.password = passwordField.textField.text ?? ""
    }

    @objc
    private func login() {
        view.endEditing(true)
        Task { @MainActor in
            await viewModel.login()
        }
    }

    /// Manual entry point: the "Have a two-factor code?" affordance under the
    /// primary CTA. Shares one presentation path with the automatic prompt raised
    /// when the server reports `totp2faRequired`.
    @objc
    private func twoFactorTapped() {
        presentTwoFactorEntry()
    }

    /// Pushes the dedicated two-factor code-entry screen. On submit we pop back
    /// and re-run the login attempt: the entered code is handed to the view model,
    /// which forwards it to the account-service login path (`totp2faToken`), so
    /// the retried login carries the TOTP code. Reused by both the manual
    /// affordance (`twoFactorTapped`) and the automatic prompt that fires when the
    /// server rejects a login with `AccountServiceLoginError.totp2faRequired`.
    private func presentTwoFactorEntry() {
        // Don't stack a second entry screen if one is already on top (the manual
        // button and the auto-prompt can both fire).
        if navigationController?.topViewController is LoginTwoFactorViewController {
            return
        }
        view.endEditing(true)
        let viewController = LoginTwoFactorViewController(
            username: viewModel.username,
            hostname: viewModel.instanceName,
            onSubmit: { [weak self] code in
                guard let self else { return }
                viewModel.totp2faToken = code
                navigationController?.popViewController(animated: true)
                Task { @MainActor in
                    await self.viewModel.login()
                }
            }
        )
        navigationController?.pushViewController(viewController, animated: true)
    }

    @objc
    private func forgotPasswordTapped() {
        let viewController = ForgotPasswordViewController(
            hostname: viewModel.instanceName,
            instance: viewModel.row.instance,
            dependencies: dependencies.own
        )
        navigationController?.pushViewController(viewController, animated: true)
    }

    @objc
    private func registerTapped() {
        let registerViewController = RegisterViewController(
            row: viewModel.row,
            dependencies: dependencies.nested
        )
        navigationController?.pushViewController(registerViewController, animated: true)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateRegisterLine()
    }

    /// Builds the "New to Spud? Create an account" attributed line, accenting
    /// the call-to-action clause.
    private func updateRegisterLine() {
        let prompt = NSLocalizedString("New to Spud? ", comment: "Login register prompt")
        let action = NSLocalizedString("Create an account", comment: "Login register CTA")

        let string = NSMutableAttributedString(
            string: prompt,
            attributes: [
                .font: UIFont.systemFont(ofSize: 13.5),
                .foregroundColor: UIColor.secondaryLabel,
            ]
        )
        string.append(NSAttributedString(
            string: action,
            attributes: [
                .font: UIFont.systemFont(ofSize: 13.5, weight: .bold),
                .foregroundColor: view.tintColor ?? .systemBlue,
            ]
        ))
        registerLineLabel.attributedText = string
    }
}
