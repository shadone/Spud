//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SpudUIKit
import UIKit

/// A row in the instance-detail "About this instance" card: icon mark +
/// `c/name` + the shared meta-community badge glyph (the same
/// `building.2.fill` glyph `SearchCommunityCell` uses, for visual consistency
/// across surfaces), an optional subtitle (the community's `title`, when set —
/// meta items carry no subscriber/activity counts, unlike
/// `InstanceCommunityRowView`'s directory-stats subtitle), and a trailing
/// chevron. Same metrics as `InstanceCommunityRowView` (38pt icon, 12pt
/// horizontal spacing, 10/13pt margins) so the two row styles read as one
/// family.
///
/// A `UIControl` (not a `UIButton.Configuration`-based button, mirroring
/// `CrossPostRowControl`): the whole row is one tap target and one
/// accessibility element, with a standard list-row tap highlight rather than a
/// button's dimming. `item` is stored (not just consumed) so a future
/// long-press context menu (Task 3) can read it back per row.
final class InstanceMetaCommunityRowView: UIControl {
    let item: MetaCommunityListItem
    /// Used only for the press-highlight tint (a soft accent wash rather than
    /// the generic system fill `CrossPostRowControl` uses) — keeps this row's
    /// tap feedback in the same accent family as the rest of the screen's
    /// interactive elements (Join/CTA buttons).
    private let accent: UIColor

    init(item: MetaCommunityListItem, accent: UIColor, onTap: @escaping () -> Void) {
        self.item = item
        self.accent = accent
        super.init(frame: .zero)

        let icon = InstanceIconMark.make(hueSeed: item.communityActorId, letterSource: item.title ?? item.name)

        let nameLabel = UILabel()
        nameLabel.text = "c/\(item.name)"
        nameLabel.font = .systemFont(ofSize: 14.5, weight: .bold)
        nameLabel.textColor = .label
        nameLabel.lineBreakMode = .byTruncatingTail

        let metaBadge = UIImageView(image: UIImage(systemName: "building.2.fill"))
        metaBadge.tintColor = .secondaryLabel
        metaBadge.contentMode = .scaleAspectFit
        metaBadge.setContentHuggingPriority(.required, for: .horizontal)

        let nameRow = UIStackView(arrangedSubviews: [nameLabel, metaBadge, UIView()])
        nameRow.axis = .horizontal
        nameRow.spacing = 6
        nameRow.alignment = .center

        var textArranged: [UIView] = [nameRow]
        if let title = item.title, !title.isEmpty {
            let subtitleLabel = UILabel()
            subtitleLabel.text = title
            subtitleLabel.font = .systemFont(ofSize: 12)
            subtitleLabel.textColor = .tertiaryLabel
            subtitleLabel.lineBreakMode = .byTruncatingTail
            textArranged.append(subtitleLabel)
        }
        let text = UIStackView(arrangedSubviews: textArranged)
        text.axis = .vertical
        text.spacing = 1
        // Purely visual; the whole row is one accessibility element and one
        // tap target (below), so touches must pass through to the control.
        text.isUserInteractionEnabled = false

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = .tertiaryLabel
        chevron.contentMode = .scaleAspectFit
        chevron.setContentHuggingPriority(.required, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [icon, text, chevron])
        stack.axis = .horizontal
        stack.spacing = 12
        stack.alignment = .center
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = .init(top: 10, left: 13, bottom: 10, right: 13)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isUserInteractionEnabled = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            icon.widthAnchor.constraint(equalToConstant: 38),
            icon.heightAnchor.constraint(equalToConstant: 38),
            // Same 16pt badge box as SearchCommunityCell's metaBadge, so the
            // glyph reads at one size across every surface that shows it.
            metaBadge.widthAnchor.constraint(equalToConstant: 16),
            metaBadge.heightAnchor.constraint(equalToConstant: 16),
        ])

        addAction(UIAction { _ in onTap() }, for: .touchUpInside)
        addTarget(self, action: #selector(highlightOn), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(highlightOff), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = String(
            format: NSLocalizedString(
                "%@, Instance community",
                comment: "VoiceOver label for an instance-detail meta-community row; %@ is the c/ community handle"
            ),
            "c/\(item.name)"
        )
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    private func highlightOn() {
        backgroundColor = accent.withAlphaComponent(0.12)
    }

    @objc
    private func highlightOff() {
        backgroundColor = .clear
    }
}
