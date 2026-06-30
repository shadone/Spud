//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SpudUIKit
import UIKit

/// A compact metadata line shown at the top of every activity cell:
/// [icon] [act label] · [relative time]
class ActivityActionHeaderView: UIView {
    // MARK: UI

    private let iconView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        iv.tintColor = .secondaryLabel
        // Scale the glyph with the footnote text style so it tracks the label
        // under Dynamic Type (including the accessibility sizes) rather than
        // staying a fixed dot beside enlarged text.
        iv.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .footnote)
        iv.adjustsImageSizeForAccessibilityContentSizeCategory = true
        return iv
    }()

    private let label: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .preferredFont(forTextStyle: .footnote)
        // Honor Dynamic Type: the verb chip is app chrome and must scale with the
        // user's preferred text size (the post body uses Spud's own text-scale).
        l.adjustsFontForContentSizeCategory = true
        l.textColor = .secondaryLabel
        l.numberOfLines = 0
        return l
    }()

    // MARK: Functions

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(act: ActivityAct, occurredAt: Date, now: Date = Date()) {
        iconView.image = UIImage(systemName: act.systemImageName)
        iconView.tintColor = act.tintColor
        label.text = "\(act.displayName) · \(occurredAt.activityRelativeString(now: now))"
    }

    // MARK: Private

    private func setup() {
        // Keep the glyph at its intrinsic (symbol-config) size so it scales with
        // Dynamic Type; never let the stack stretch or squeeze it.
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [iconView, label])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 4
        stack.alignment = .center

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}

extension ActivityAct {
    /// A natural-language verb for VoiceOver, phrased as a completed first-person
    /// action ("You upvoted") so the composed row label reads as one utterance.
    var accessibilityVerb: String {
        switch self {
        case .upvote: NSLocalizedString("You upvoted", comment: "Activity VoiceOver verb")
        case .downvote: NSLocalizedString("You downvoted", comment: "Activity VoiceOver verb")
        case .comment: NSLocalizedString("You commented", comment: "Activity VoiceOver verb")
        case .post: NSLocalizedString("You posted", comment: "Activity VoiceOver verb")
        case .save: NSLocalizedString("You saved", comment: "Activity VoiceOver verb")
        case .read: NSLocalizedString("You read", comment: "Activity VoiceOver verb")
        case .seen: NSLocalizedString("You saw", comment: "Activity VoiceOver verb")
        case .hide: NSLocalizedString("You hid", comment: "Activity VoiceOver verb")
        }
    }

    var displayName: String {
        switch self {
        case .upvote: NSLocalizedString("Upvoted", comment: "Activity act label")
        case .downvote: NSLocalizedString("Downvoted", comment: "Activity act label")
        case .comment: NSLocalizedString("Commented", comment: "Activity act label")
        case .post: NSLocalizedString("Posted", comment: "Activity act label")
        case .save: NSLocalizedString("Saved", comment: "Activity act label")
        case .read: NSLocalizedString("Read", comment: "Activity act label")
        case .seen: NSLocalizedString("Seen", comment: "Activity act label")
        case .hide: NSLocalizedString("Hidden", comment: "Activity act label")
        }
    }

    var systemImageName: String {
        switch self {
        case .upvote: "arrow.up"
        case .downvote: "arrow.down"
        case .comment: "text.bubble"
        case .post: "doc.text"
        case .save: "bookmark.fill"
        case .read: "book"
        case .seen: "eye"
        case .hide: "eye.slash"
        }
    }

    var tintColor: UIColor {
        switch self {
        case .upvote: ThemeManager.currentAccentColor
        case .downvote: GeneralAppearance.downColor
        case .comment, .post, .save, .read, .seen, .hide: .secondaryLabel
        }
    }
}

extension Date {
    /// Returns a short relative-time string ("just now", "5m ago", "2h ago", "3d ago")
    /// computed against the given reference instant. Tests inject a fixed `now` so
    /// the rendered text is deterministic; production passes `Date()` (the default).
    func activityRelativeString(now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(self)
        if seconds < 60 { return NSLocalizedString("just now", comment: "Activity relative time") }
        if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return String(format: NSLocalizedString("%dm ago", comment: "Activity relative time: minutes"), minutes)
        }
        if seconds < 86400 {
            let hours = Int(seconds / 3600)
            return String(format: NSLocalizedString("%dh ago", comment: "Activity relative time: hours"), hours)
        }
        let days = Int(seconds / 86400)
        return String(format: NSLocalizedString("%dd ago", comment: "Activity relative time: days"), days)
    }
}
