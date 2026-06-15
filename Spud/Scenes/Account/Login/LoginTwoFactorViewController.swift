//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUIKit
import UIKit

/// Two-factor (TOTP) code-entry screen. Pushed from the login screen when the
/// user indicates their account is protected by an authenticator app. Matches
/// the Spud Design `LoginTwoFactor` mockup: a centred lock tile, an "Enter your
/// code" title, an explanatory body naming the account, a row of six code
/// "cells", a "Verify" primary CTA, and a "Paste from clipboard" affordance.
///
/// The six cells are a visual veneer over a single hidden `UITextField`. The
/// field drives real keyboard input plus iOS one-time-code autofill (SMS / TOTP
/// suggestion bar) via `.oneTimeCode`, while the cells display the typed digits
/// as separate boxes. The cell at the current input index shows an active
/// border + caret.
final class LoginTwoFactorViewController: UIViewController {
    /// Number of digits in a TOTP code.
    private static let codeLength = 6

    private let username: String
    private let hostname: String

    /// Called with the entered six-digit code when the user taps "Verify" (or
    /// when the field autofills a full code). The presenter is responsible for
    /// completing login with the token and dismissing this screen.
    private let onSubmit: (String) -> Void

    /// The digits typed so far (0...6 characters, digits only).
    private var code: String = "" {
        didSet { updateCells() }
    }

    // MARK: UI Properties

    /// The 64pt circle holding the lock glyph: a low-alpha `tintColor` fill with
    /// a ~1.5pt `tintColor` border. Colors are applied in `applyTintColors()` so
    /// they track `tintColor` changes.
    private lazy var lockTile: UIView = {
        let tile = UIView()
        tile.translatesAutoresizingMaskIntoConstraints = false
        tile.layer.cornerRadius = 32
        tile.layer.borderWidth = 1.5
        return tile
    }()

    private lazy var lockImageView: UIImageView = {
        let configuration = UIImage.SymbolConfiguration(pointSize: 26, weight: .regular)
        let imageView = UIImageView(image: UIImage(systemName: "lock", withConfiguration: configuration))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .center
        // No explicit tintColor: the lock inherits the app accent from the
        // view hierarchy's `tintColor`.
        return imageView
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 20, weight: .heavy)
        label.textColor = .label
        label.textAlignment = .center
        label.numberOfLines = 0
        label.text = NSLocalizedString(
            "Enter your code",
            comment: "Two-factor screen title"
        )
        return label
    }()

    /// Body copy: "Open your authenticator app and enter the 6-digit code for
    /// <username>@<host>." with the account portion drawn in `.label` for
    /// emphasis against the surrounding `.secondaryLabel` body.
    private lazy var bodyLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.numberOfLines = 0
        label.attributedText = makeBodyText()
        return label
    }()

    /// Single hidden field that receives keystrokes and one-time-code autofill.
    /// The visible cells mirror its value. It is added to the hierarchy (off the
    /// visible area is unnecessary — it is simply zero-size / transparent) so it
    /// can become first responder and present the keyboard.
    private lazy var hiddenTextField: UITextField = {
        let textField = UITextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.keyboardType = .numberPad
        textField.textContentType = .oneTimeCode
        textField.autocorrectionType = .no
        textField.tintColor = .clear
        textField.textColor = .clear
        textField.backgroundColor = .clear
        textField.delegate = self
        textField.addTarget(self, action: #selector(codeFieldChanged), for: .editingChanged)
        return textField
    }()

    /// The six visible digit cells, left to right.
    private lazy var cells: [CodeCell] = (0..<Self.codeLength).map { _ in CodeCell() }

    private lazy var cellsStackView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: cells)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .fill
        stackView.distribution = .fillEqually
        stackView.spacing = 8
        return stackView
    }()

    private lazy var verifyButton: OnboardingPrimaryButton = {
        let button = OnboardingPrimaryButton(
            title: NSLocalizedString("Verify", comment: "Two-factor primary CTA")
        )
        button.addTarget(self, action: #selector(verifyTapped), for: .touchUpInside)
        return button
    }()

    private lazy var pasteButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.attributedTitle = AttributedString(
            NSLocalizedString("Paste from clipboard", comment: "Two-factor paste affordance"),
            attributes: AttributeContainer([
                .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
            ])
        )

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(pasteTapped), for: .touchUpInside)
        return button
    }()

    // MARK: Functions

    init(
        username: String,
        hostname: String,
        onSubmit: @escaping (String) -> Void
    ) {
        self.username = username
        self.hostname = hostname
        self.onSubmit = onSubmit

        super.init(nibName: nil, bundle: nil)

        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        navigationItem.title = NSLocalizedString("Two-factor", comment: "Two-factor screen title")

        view.backgroundColor = Theme.background

        lockTile.addSubview(lockImageView)

        // Centred column near the top: lock tile, title, body.
        let headerStackView = UIStackView(arrangedSubviews: [lockTile, titleLabel, bodyLabel])
        headerStackView.translatesAutoresizingMaskIntoConstraints = false
        headerStackView.axis = .vertical
        headerStackView.alignment = .center
        headerStackView.spacing = 8
        headerStackView.setCustomSpacing(16, after: lockTile)

        view.addSubview(headerStackView)
        view.addSubview(hiddenTextField)
        view.addSubview(cellsStackView)
        view.addSubview(verifyButton)
        view.addSubview(pasteButton)

        NSLayoutConstraint.activate([
            lockTile.widthAnchor.constraint(equalToConstant: 64),
            lockTile.heightAnchor.constraint(equalToConstant: 64),
            lockImageView.centerXAnchor.constraint(equalTo: lockTile.centerXAnchor),
            lockImageView.centerYAnchor.constraint(equalTo: lockTile.centerYAnchor),

            headerStackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            headerStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            headerStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            cellsStackView.topAnchor.constraint(equalTo: headerStackView.bottomAnchor, constant: 22),
            cellsStackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cellsStackView.heightAnchor.constraint(equalToConstant: 54),

            // The hidden field is pinned over the cells so an autofill / paste
            // affordance lands in roughly the right place; it is invisible.
            hiddenTextField.topAnchor.constraint(equalTo: cellsStackView.topAnchor),
            hiddenTextField.bottomAnchor.constraint(equalTo: cellsStackView.bottomAnchor),
            hiddenTextField.leadingAnchor.constraint(equalTo: cellsStackView.leadingAnchor),
            hiddenTextField.trailingAnchor.constraint(equalTo: cellsStackView.trailingAnchor),

            verifyButton.topAnchor.constraint(equalTo: cellsStackView.bottomAnchor, constant: 22),
            verifyButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            verifyButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            verifyButton.heightAnchor.constraint(equalToConstant: 52),

            pasteButton.topAnchor.constraint(equalTo: verifyButton.bottomAnchor, constant: 14),
            pasteButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])

        // The hidden field must stay behind the cells so taps anywhere on the
        // cell row are forwarded (via the tap recognizer below) rather than
        // hitting the field's own caret region.
        view.sendSubviewToBack(hiddenTextField)

        // Tapping anywhere on the cell row focuses the hidden field.
        let tap = UITapGestureRecognizer(target: self, action: #selector(focusCodeField))
        cellsStackView.addGestureRecognizer(tap)

        applyTintColors()
        updateCells()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hiddenTextField.becomeFirstResponder()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        // Re-derive the accent-driven lock colors on every layout pass so they
        // track `tintColor` and light/dark changes.
        applyTintColors()
    }

    /// Re-applies the accent-derived colors on the lock tile so they track
    /// `tintColor` (and light/dark) changes.
    private func applyTintColors() {
        let accent = view.tintColor ?? .systemBlue
        lockTile.backgroundColor = accent.withAlphaComponent(0.12)
        lockTile.layer.borderColor = accent.withAlphaComponent(0.27).cgColor
    }

    private func makeBodyText() -> NSAttributedString {
        let account = "\(username)@\(hostname)"
        let template = NSLocalizedString(
            "Open your authenticator app and enter the 6-digit code for %@.",
            comment: "Two-factor body, %@ is the account (username@host)"
        )

        let string = NSMutableAttributedString(
            string: String(format: template, account),
            attributes: [
                .font: UIFont.systemFont(ofSize: 13.5),
                .foregroundColor: UIColor.secondaryLabel,
            ]
        )

        // Emphasise the account portion in `.label`.
        let accountRange = (string.string as NSString).range(of: account)
        if accountRange.location != NSNotFound {
            string.addAttributes(
                [
                    .font: UIFont.systemFont(ofSize: 13.5, weight: .semibold),
                    .foregroundColor: UIColor.label,
                ],
                range: accountRange
            )
        }
        return string
    }

    // MARK: Cell state

    /// Mirrors `code` into the visible cells and updates the active-cell border,
    /// the caret, and the Verify button's enabled state.
    private func updateCells() {
        let digits = Array(code)
        let activeIndex = digits.count
        for (index, cell) in cells.enumerated() {
            let digit = index < digits.count ? String(digits[index]) : ""
            // The active cell is the next-empty one, but only while the field is
            // first responder; a full code has no active cell.
            let isActive = index == activeIndex && hiddenTextField.isFirstResponder
            cell.configure(digit: digit, isActive: isActive)
        }
        verifyButton.isEnabled = code.count == Self.codeLength
    }

    // MARK: Actions

    @objc
    private func focusCodeField() {
        hiddenTextField.becomeFirstResponder()
    }

    @objc
    private func codeFieldChanged() {
        let sanitized = String((hiddenTextField.text ?? "").filter(\.isNumber).prefix(Self.codeLength))
        if hiddenTextField.text != sanitized {
            hiddenTextField.text = sanitized
        }
        code = sanitized

        // Auto-submit on a full autofilled / typed code for a one-tap flow.
        if code.count == Self.codeLength {
            view.endEditing(true)
            submit()
        }
    }

    @objc
    private func verifyTapped() {
        view.endEditing(true)
        submit()
    }

    @objc
    private func pasteTapped() {
        guard let pasteboard = UIPasteboard.general.string else { return }
        let digits = String(pasteboard.filter(\.isNumber).prefix(Self.codeLength))
        guard !digits.isEmpty else { return }
        hiddenTextField.text = digits
        code = digits
        if code.count == Self.codeLength {
            view.endEditing(true)
            submit()
        }
    }

    private func submit() {
        guard code.count == Self.codeLength else { return }
        onSubmit(code)
    }

    #if DEBUG
    /// Test-only: pre-fills the code and forces the active-cell state so snapshot
    /// references can show a partially-entered code with the caret/active border
    /// without driving a live keyboard / first-responder.
    func setCodeForTesting(_ digits: String, activeCellVisible: Bool) {
        let sanitized = String(digits.filter(\.isNumber).prefix(Self.codeLength))
        hiddenTextField.text = sanitized
        let activeIndex = sanitized.count
        for (index, cell) in cells.enumerated() {
            let digit = index < sanitized.count ? String(Array(sanitized)[index]) : ""
            let isActive = activeCellVisible && index == activeIndex
            cell.configure(digit: digit, isActive: isActive)
        }
        verifyButton.isEnabled = sanitized.count == Self.codeLength
    }
    #endif
}

extension LoginTwoFactorViewController: UITextFieldDelegate {
    func textFieldDidBeginEditing(_: UITextField) {
        updateCells()
    }

    func textFieldDidEndEditing(_: UITextField) {
        updateCells()
    }
}

/// A single code "cell": a 44x54 rounded box with a large mono digit. At rest the
/// border is `.separator`; the active (next-empty) cell shows a `tintColor`
/// border and a blinking caret. Matches the design's `LoginTwoFactor` cells.
private final class CodeCell: UIView {
    private let digitLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedSystemFont(ofSize: 22, weight: .bold)
        label.textColor = .label
        label.textAlignment = .center
        return label
    }()

    /// A thin vertical caret shown on the active, empty cell.
    private let caretView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 1
        view.isHidden = true
        return view
    }()

    private var isActive = false

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 11
        layer.cornerCurve = .continuous
        layer.borderWidth = 1.5

        addSubview(digitLabel)
        addSubview(caretView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 44),
            digitLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            digitLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            caretView.centerXAnchor.constraint(equalTo: centerXAnchor),
            caretView.centerYAnchor.constraint(equalTo: centerYAnchor),
            caretView.widthAnchor.constraint(equalToConstant: 2),
            caretView.heightAnchor.constraint(equalToConstant: 22),
        ])

        updateBorderColor()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        updateBorderColor()
        caretView.backgroundColor = tintColor
    }

    func configure(digit: String, isActive: Bool) {
        digitLabel.text = digit
        self.isActive = isActive
        // The caret shows on the active cell only when it has no digit yet.
        caretView.isHidden = !(isActive && digit.isEmpty)
        updateBorderColor()
    }

    private func updateBorderColor() {
        layer.borderColor = (isActive ? tintColor : UIColor.separator).cgColor
        caretView.backgroundColor = tintColor
    }
}
