//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

// Small, reusable native primitives shared by the onboarding / login flow so
// the screens stay visually consistent. Mirrors the design's `PrimaryBtn` and
// labeled `Field` primitives (see the Spud Design `screens-common` / `login`
// mockups). The accent is always read from `tintColor` so the app accent flows
// through every control.

/// The design's `PrimaryBtn`: a 52pt-tall, accent-filled, 17pt-semibold pill
/// with a continuous 14pt corner. Matches the `OnboardingWelcomeViewController`
/// CTA family (`UIButton.Configuration.filled()` + large corner) so the two
/// screens read as one flow.
final class OnboardingPrimaryButton: UIButton {
    init(title: String) {
        super.init(frame: .zero)

        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.cornerStyle = .large
        configuration.contentInsets = .init(top: 15, leading: 16, bottom: 15, trailing: 16)
        self.configuration = configuration

        translatesAutoresizingMaskIntoConstraints = false
        configurationUpdateHandler = { button in
            var updated = button.configuration
            updated?.baseBackgroundColor = button.tintColor
            updated?.attributedTitle = AttributedString(
                title,
                attributes: AttributeContainer([
                    .font: UIFont.systemFont(ofSize: 17, weight: .semibold),
                ])
            )
            button.configuration = updated
        }

        heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// The design's labeled `Field`: a 12pt/600 secondary caption above a 48pt-tall
/// rounded (radius 12) container holding a `UITextField`, with a 1pt border that
/// is `.separator` at rest, `tintColor` while first responder, and `.systemRed`
/// in an error state. An optional 12pt red error caption appears below, and an
/// optional trailing eye toggle reveals secure text.
final class OnboardingLabeledField: UIView {
    /// The wrapped text field. Callers configure keyboard type / content type /
    /// delegate and read `text` directly off it.
    let textField = UITextField()

    /// Error message shown under the field. Setting a non-nil, non-empty value
    /// puts the field in its error (red border) state; nil clears it.
    var errorText: String? {
        didSet {
            errorLabel.text = errorText
            let hasError = !(errorText ?? "").isEmpty
            errorLabel.isHidden = !hasError
            updateBorderColor()
        }
    }

    /// Placeholder convenience forwarder.
    var placeholder: String? {
        get { textField.placeholder }
        set { textField.placeholder = newValue }
    }

    private let captionLabel = UILabel()
    private let container = UIView()
    private let errorLabel = UILabel()
    private lazy var eyeButton = UIButton(type: .system)
    private let showsEyeToggle: Bool

    init(caption: String, isSecure: Bool = false) {
        showsEyeToggle = isSecure
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        captionLabel.translatesAutoresizingMaskIntoConstraints = false
        captionLabel.text = caption
        captionLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        captionLabel.textColor = .secondaryLabel

        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .secondarySystemBackground
        container.layer.cornerRadius = 12
        container.layer.cornerCurve = .continuous
        container.layer.borderWidth = 1

        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.borderStyle = .none
        textField.font = .systemFont(ofSize: 15)
        textField.textColor = .label
        textField.isSecureTextEntry = isSecure
        textField.delegate = self

        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.font = .systemFont(ofSize: 12)
        errorLabel.textColor = .systemRed
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true

        let stackView = UIStackView(arrangedSubviews: [captionLabel, container, errorLabel])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 6
        stackView.setCustomSpacing(5, after: container)
        addSubview(stackView)

        container.addSubview(textField)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),

            // 2pt left inset on the caption, matching the design.
            captionLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),

            container.heightAnchor.constraint(equalToConstant: 48),

            textField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            textField.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        if showsEyeToggle {
            eyeButton.translatesAutoresizingMaskIntoConstraints = false
            eyeButton.tintColor = .secondaryLabel
            eyeButton.addTarget(self, action: #selector(toggleSecureEntry), for: .touchUpInside)
            container.addSubview(eyeButton)
            NSLayoutConstraint.activate([
                eyeButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
                eyeButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                eyeButton.leadingAnchor.constraint(equalTo: textField.trailingAnchor, constant: 8),
                eyeButton.widthAnchor.constraint(equalToConstant: 24),
            ])
            updateEyeImage()
        } else {
            textField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14).isActive = true
        }

        updateBorderColor()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        updateBorderColor()
    }

    private func updateBorderColor() {
        let color: UIColor
        if !(errorText ?? "").isEmpty {
            color = .systemRed
        } else if textField.isFirstResponder {
            color = tintColor
        } else {
            color = .separator
        }
        container.layer.borderColor = color.cgColor
    }

    @objc
    private func toggleSecureEntry() {
        textField.isSecureTextEntry.toggle()
        updateEyeImage()
    }

    private func updateEyeImage() {
        let symbolName = textField.isSecureTextEntry ? "eye" : "eye.slash"
        eyeButton.setImage(UIImage(systemName: symbolName), for: .normal)
    }
}

extension OnboardingLabeledField: UITextFieldDelegate {
    func textFieldDidBeginEditing(_: UITextField) {
        // Clear any error once the user starts correcting the field.
        if errorText != nil {
            errorText = nil
        }
        updateBorderColor()
    }

    func textFieldDidEndEditing(_: UITextField) {
        updateBorderColor()
    }
}
