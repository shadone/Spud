//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SpudUIKit
import UIKit

/// Subtitle string for a community row: "N subscribers · M/wk". The lemmyverse
/// dataset has no posts/week figure, so weekly-active users stand in for it.
enum InstanceCommunityDisplay {
    static func subtitle(for row: CommunityListRow) -> String {
        let subs = InstanceHealthStyle.formatCount(row.numberOfSubscribers)
        let week = InstanceHealthStyle.formatCount(row.usersActiveWeek)
        return "\(subs) subscribers · \(week)/wk"
    }
}

/// A community row: square icon mark + `c/name` + subtitle, trailed by either a
/// Join/Joined pill (explore) or a chevron (onboarding's top-3 list).
final class InstanceCommunityRowView: UIView {
    enum Action { case join, chevron }

    var onJoinTapped: (() -> Void)?

    private let joinButton = UIButton(type: .system)
    private var joined: Bool
    private let accent: UIColor
    private let action: Action

    init(row: CommunityListRow, action: Action, joined: Bool, accent: UIColor) {
        self.joined = joined
        self.accent = accent
        self.action = action
        super.init(frame: .zero)

        let icon = InstanceCommunityRowView.iconMark(for: row)

        let nameLabel = UILabel()
        nameLabel.text = "c/\(row.name)"
        nameLabel.font = .systemFont(ofSize: 14.5, weight: .bold)
        nameLabel.textColor = .label
        nameLabel.lineBreakMode = .byTruncatingTail

        let subtitle = UILabel()
        subtitle.text = InstanceCommunityDisplay.subtitle(for: row)
        subtitle.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        subtitle.textColor = .tertiaryLabel

        let text = UIStackView(arrangedSubviews: [nameLabel, subtitle])
        text.axis = .vertical
        text.spacing = 1

        let trailing: UIView
        switch action {
        case .join:
            configureJoinButton()
            trailing = joinButton
        case .chevron:
            let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
            chevron.tintColor = .tertiaryLabel
            chevron.contentMode = .scaleAspectFit
            chevron.setContentHuggingPriority(.required, for: .horizontal)
            trailing = chevron
        }

        let stack = UIStackView(arrangedSubviews: [icon, text, trailing])
        stack.axis = .horizontal
        stack.spacing = 12
        stack.alignment = .center
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = .init(top: 10, left: 13, bottom: 10, right: 13)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            icon.widthAnchor.constraint(equalToConstant: 38),
            icon.heightAnchor.constraint(equalToConstant: 38),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Optimistically reflect a join/leave without rebuilding the row.
    func setJoined(_ value: Bool) {
        guard action == .join else { return }
        joined = value
        configureJoinButton()
    }

    private func configureJoinButton() {
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.buttonSize = .small
        config.imagePadding = 4
        if joined {
            config.title = NSLocalizedString("Joined", comment: "Instance community joined pill")
            config.image = UIImage(systemName: "checkmark")
            config.baseBackgroundColor = .secondarySystemBackground
            config.baseForegroundColor = .secondaryLabel
        } else {
            config.title = NSLocalizedString("Join", comment: "Instance community join pill")
            config.image = UIImage(systemName: "plus")
            config.baseBackgroundColor = accent
            config.baseForegroundColor = .white
        }
        joinButton.configuration = config
        joinButton.setContentHuggingPriority(.required, for: .horizontal)
        joinButton.removeTarget(nil, action: nil, for: .touchUpInside)
        joinButton.addAction(UIAction { [weak self] _ in self?.onJoinTapped?() }, for: .touchUpInside)
        joinButton.accessibilityLabel = joined
            ? NSLocalizedString("Joined", comment: "Instance community joined pill a11y")
            : NSLocalizedString("Join", comment: "Instance community join pill a11y")
    }

    private static func iconMark(for row: CommunityListRow) -> UIView {
        InstanceIconMark.make(hueSeed: row.instanceHost, letterSource: row.title ?? row.name)
    }
}
