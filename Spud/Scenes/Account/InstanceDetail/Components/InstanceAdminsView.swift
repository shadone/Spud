//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SpudUIKit
import UIKit

enum InstanceAdminsState: Equatable {
    case loading
    case unavailable
    case anonymous
    case admins([SiteAdminRecord])
}

/// "Admins" section: a header + a card listing admins, or one of the degraded
/// states (loading / unavailable / anonymous-operator warning).
final class InstanceAdminsView: UIView {
    private let header = InstanceSectionHeader()
    private let card = UIView()
    private let stack = UIStackView()
    /// Stored so `layoutSubviews` can re-resolve the card's border `CGColor`
    /// after a light/dark trait change (a baked `CGColor` would not update).
    private var cardBorderColor: UIColor?

    override init(frame: CGRect) {
        super.init(frame: frame)
        let outer = UIStackView(arrangedSubviews: [header, card])
        outer.axis = .vertical
        outer.spacing = 8
        outer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(outer)
        NSLayoutConstraint.activate([
            outer.topAnchor.constraint(equalTo: topAnchor),
            outer.leadingAnchor.constraint(equalTo: leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: trailingAnchor),
            outer.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        card.layer.cornerRadius = 14
        card.layer.cornerCurve = .continuous
        card.clipsToBounds = true
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Re-resolve the dynamic border colour against the current trait
        // collection so the anonymous-state border follows live light/dark switches.
        card.layer.borderColor = cardBorderColor?.cgColor
    }

    func update(_ state: InstanceAdminsState) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        card.layer.borderWidth = 0
        cardBorderColor = nil
        card.layer.borderColor = nil
        switch state {
        case .loading:
            header.configure(title: "Admins", count: nil)
            card.backgroundColor = Theme.secondaryGroupedBackground
            stack.addArrangedSubview(messageRow("Loading…", color: .tertiaryLabel))
        case .unavailable:
            header.configure(title: "Admins", count: nil)
            card.backgroundColor = Theme.secondaryGroupedBackground
            stack.addArrangedSubview(messageRow("Admin list unavailable for this server.", color: .tertiaryLabel))
        case .anonymous:
            header.configure(title: "Admins", count: 0)
            card.backgroundColor = UIColor.systemRed.withAlphaComponent(0.10)
            card.layer.borderWidth = 1
            cardBorderColor = UIColor.systemRed.withAlphaComponent(0.24)
            card.layer.borderColor = cardBorderColor?.cgColor
            let row = warningRow("No admins are publicly listed — operator is anonymous.")
            stack.addArrangedSubview(row)
        case let .admins(admins):
            header.configure(title: "Admins", count: admins.count)
            card.backgroundColor = Theme.secondaryGroupedBackground
            for (index, admin) in admins.enumerated() {
                stack.addArrangedSubview(adminRow(admin))
                if index < admins.count - 1 {
                    stack.addArrangedSubview(hairline())
                }
            }
        }
    }

    private func messageRow(_ text: String, color: UIColor) -> UIView {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 13.5)
        label.textColor = color
        label.numberOfLines = 0
        return inset(label, insets: .init(top: 14, left: 14, bottom: 14, right: 14))
    }

    private func warningRow(_ text: String) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: "exclamationmark.triangle.fill"))
        icon.tintColor = .systemRed
        icon.contentMode = .scaleAspectFit
        icon.setContentHuggingPriority(.required, for: .horizontal)
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .systemRed
        label.numberOfLines = 0
        let row = UIStackView(arrangedSubviews: [icon, label])
        row.axis = .horizontal
        row.spacing = 10
        row.alignment = .center
        NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 16), icon.heightAnchor.constraint(equalToConstant: 16)])
        return inset(row, insets: .init(top: 12, left: 14, bottom: 12, right: 14))
    }

    private func adminRow(_ admin: SiteAdminRecord) -> UIView {
        let avatar = InstancePersonAvatarView(seed: admin.personName)
        avatar.translatesAutoresizingMaskIntoConstraints = false
        let name = UILabel()
        name.text = admin.label
        name.font = .systemFont(ofSize: 14.5, weight: .bold)
        name.textColor = .label
        let handle = UILabel()
        handle.text = "@\(admin.personName)"
        handle.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        handle.textColor = .tertiaryLabel
        let text = UIStackView(arrangedSubviews: [name, handle])
        text.axis = .vertical
        text.spacing = 1
        let role = PaddedChipLabel(text: admin.roleLabel)
        let row = UIStackView(arrangedSubviews: [avatar, text, role])
        row.axis = .horizontal
        row.spacing = 11
        row.alignment = .center
        NSLayoutConstraint.activate([avatar.widthAnchor.constraint(equalToConstant: 36), avatar.heightAnchor.constraint(equalToConstant: 36)])
        return inset(row, insets: .init(top: 9, left: 13, bottom: 9, right: 13))
    }

    private func hairline() -> UIView {
        let line = UIView()
        line.backgroundColor = .separator
        line.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        return inset(line, insets: .init(top: 0, left: 13, bottom: 0, right: 0))
    }

    private func inset(_ view: UIView, insets: UIEdgeInsets) -> UIView {
        let stack = UIStackView(arrangedSubviews: [view])
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = insets
        return stack
    }
}

/// Uppercase section label with an optional count, e.g. "ADMINS  3".
final class InstanceSectionHeader: UIView {
    private let titleLabel = UILabel()
    private let countLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.font = .systemFont(ofSize: 12, weight: .bold)
        titleLabel.textColor = .tertiaryLabel
        countLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .bold)
        countLabel.textColor = .tertiaryLabel
        let stack = UIStackView(arrangedSubviews: [titleLabel, countLabel, UIView()])
        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .firstBaseline
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, count: Int?) {
        titleLabel.text = title.uppercased()
        countLabel.text = count.map { "\($0)" }
        countLabel.isHidden = count == nil
    }
}

/// A round placeholder avatar mark seeded by a string (deterministic hue).
final class InstancePersonAvatarView: UIView {
    init(seed: String) {
        super.init(frame: .zero)
        let hue = CGFloat(seed.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 360) / 360
        backgroundColor = UIColor(hue: hue, saturation: 0.45, brightness: 0.55, alpha: 1)
        clipsToBounds = true
        let letter = UILabel()
        letter.text = String(seed.prefix(1)).uppercased()
        letter.font = .systemFont(ofSize: 15, weight: .bold)
        letter.textColor = .white
        letter.translatesAutoresizingMaskIntoConstraints = false
        addSubview(letter)
        NSLayoutConstraint.activate([
            letter.centerXAnchor.constraint(equalTo: centerXAnchor),
            letter.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }
}

/// A small rounded role chip ("Owner" / "Admin").
final class PaddedChipLabel: UIView {
    init(text: String) {
        super.init(frame: .zero)
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 7
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 11, weight: .bold)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        setContentHuggingPriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
