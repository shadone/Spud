//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUIKit
import UIKit

/// A pinned footer of account actions shown below the signed-in profile:
/// Saved, Settings, and a destructive Log out. Layout-only; the owning view
/// controller wires the callbacks.
final class AccountActionsFooterView: UIView {
    var savedTapped: (() -> Void)?
    var settingsTapped: (() -> Void)?
    var logoutTapped: (() -> Void)?

    private lazy var savedButton = makeButton(
        title: NSLocalizedString("Saved", comment: "Account footer: open saved posts"),
        systemImage: "bookmark",
        action: #selector(didTapSaved)
    )

    private lazy var settingsButton = makeButton(
        title: NSLocalizedString("Settings", comment: "Account footer: open settings"),
        systemImage: "gearshape",
        action: #selector(didTapSettings)
    )

    private lazy var logoutButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.title = NSLocalizedString("Log out", comment: "Account footer: log out")
        config.image = UIImage(systemName: "rectangle.portrait.and.arrow.right")
        config.imagePadding = 6
        config.baseForegroundColor = .systemRed
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(didTapLogout), for: .touchUpInside)
        return button
    }()

    private lazy var separator: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .separator
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        backgroundColor = Theme.background

        let topRow = UIStackView(arrangedSubviews: [savedButton, settingsButton])
        topRow.translatesAutoresizingMaskIntoConstraints = false
        topRow.axis = .horizontal
        topRow.distribution = .fillEqually
        topRow.spacing = 12

        let stack = UIStackView(arrangedSubviews: [topRow, logoutButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 4

        addSubview(separator)
        addSubview(stack)

        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),

            stack.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    private func makeButton(title: String, systemImage: String, action: Selector) -> UIButton {
        var config = UIButton.Configuration.gray()
        config.title = title
        config.image = UIImage(systemName: systemImage)
        config.imagePadding = 6
        config.cornerStyle = .medium
        config.buttonSize = .medium
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    @objc
    private func didTapSaved() {
        savedTapped?()
    }

    @objc
    private func didTapSettings() {
        settingsTapped?()
    }

    @objc
    private func didTapLogout() {
        logoutTapped?()
    }
}
