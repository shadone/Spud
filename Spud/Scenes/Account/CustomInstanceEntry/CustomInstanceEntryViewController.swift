//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import SpudUIKit
import UIKit

/// Lets a user type the address of a Lemmy instance that isn't in the
/// bundled/Explorer directory (e.g. a private, non-federated server) and
/// continue straight to the normal login/register flow for it. Reached from
/// both `SiteListViewController`'s "Add your own instance" row and
/// `OnboardingHomeBaseViewController`'s "Enter instance address" footer row.
///
/// On a valid address this pushes `LoginViewController` with a bare row built
/// by `SiteListRow.forTypedInstance` - the same construction the `MainWindow`
/// DEBUG UI-test seam uses, since the entire login/register path is already
/// keyed on a bare `InstanceActorId` with no directory-membership gate.
final class CustomInstanceEntryViewController: UIViewController {
    typealias Dependencies = LoginViewController.Dependencies
    private let dependencies: Dependencies

    private let viewModel = CustomInstanceEntryViewModel()
    private var observationTasks: [Task<Void, Never>] = []

    // MARK: UI Properties

    private lazy var headerIconView: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .secondarySystemBackground
        container.layer.cornerRadius = 16
        container.layer.cornerCurve = .continuous

        let configuration = UIImage.SymbolConfiguration(pointSize: 26, weight: .semibold)
        let imageView = UIImageView(image: UIImage(systemName: "network", withConfiguration: configuration))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .center
        // No explicit tintColor: inherits the app accent.
        container.addSubview(imageView)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 64),
            container.heightAnchor.constraint(equalToConstant: 64),
            imageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 22, weight: .heavy)
        label.textColor = .label
        label.numberOfLines = 0
        label.textAlignment = .center
        label.text = NSLocalizedString("Add your own instance", comment: "Custom instance entry screen title")
        return label
    }()

    private lazy var subtitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.textAlignment = .center
        label.text = NSLocalizedString(
            "Enter the address of any Lemmy instance.",
            comment: "Custom instance entry helper text"
        )
        return label
    }()

    private lazy var addressField: OnboardingLabeledField = {
        let field = OnboardingLabeledField(
            caption: NSLocalizedString("Instance address", comment: "Custom instance entry field caption"),
            leadingSymbolName: "globe"
        )
        field.placeholder = "lemmy.example.com"
        field.textField.keyboardType = .URL
        field.textField.autocapitalizationType = .none
        field.textField.autocorrectionType = .no
        field.textField.textContentType = .URL
        field.textField.returnKeyType = .go
        field.textField.accessibilityIdentifier = "custom-instance-address"
        field.textField.addTarget(self, action: #selector(addressChanged), for: .editingChanged)
        // `.editingDidEndOnExit` (return key) rather than becoming the
        // `UITextFieldDelegate` - the field is already its own delegate
        // (border-color/focus tracking in `OnboardingLabeledField`), and a
        // second delegate assignment here would silently replace it.
        field.textField.addTarget(self, action: #selector(continueTapped), for: .editingDidEndOnExit)
        return field
    }()

    private lazy var continueButton: OnboardingPrimaryButton = {
        let button = OnboardingPrimaryButton(
            title: NSLocalizedString("Continue", comment: "Custom instance entry primary CTA")
        )
        button.accessibilityIdentifier = "custom-instance-continue"
        button.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)
        return button
    }()

    // MARK: Functions

    init(dependencies: Dependencies) {
        self.dependencies = dependencies

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
        navigationItem.title = NSLocalizedString("Add Instance", comment: "Custom instance entry nav title")
        view.backgroundColor = Theme.background

        // The header icon hugs its own size and is centered via a horizontal
        // stack rather than stretching to the form's full width.
        let headerRow = UIStackView(arrangedSubviews: [UIView(), headerIconView, UIView()])
        headerRow.axis = .horizontal
        headerRow.distribution = .equalCentering

        let stackView = UIStackView(arrangedSubviews: [
            headerRow,
            titleLabel,
            subtitleLabel,
            addressField,
            continueButton,
        ])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 13
        stackView.setCustomSpacing(16, after: headerRow)
        stackView.setCustomSpacing(6, after: titleLabel)
        stackView.setCustomSpacing(26, after: subtitleLabel)
        stackView.setCustomSpacing(20, after: addressField)

        view.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 28),
        ])
    }

    private func bindViewModel() {
        observationTasks.append(Task { @MainActor [weak self, viewModel] in
            for await enabled in ObservationStream.values(of: { viewModel.continueEnabled }) {
                self?.continueButton.isEnabled = enabled
            }
        })

        observationTasks.append(Task { @MainActor [weak self, viewModel] in
            for await error in ObservationStream.values(of: { viewModel.errorText }) {
                self?.addressField.errorText = error
            }
        })
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        addressField.textField.becomeFirstResponder()
    }

    // MARK: Actions

    @objc
    private func addressChanged() {
        viewModel.addressText = addressField.textField.text ?? ""
    }

    @objc
    private func continueTapped() {
        view.endEditing(true)
        guard let instance = viewModel.resolveInstance() else { return }

        let row = SiteListRow.forTypedInstance(instance)
        let loginViewController = LoginViewController(row: row, dependencies: dependencies)
        navigationController?.pushViewController(loginViewController, animated: true)
    }
}
