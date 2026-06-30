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
        return iv
    }()

    private let label: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .preferredFont(forTextStyle: .footnote)
        l.textColor = .secondaryLabel
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

    func configure(act: ActivityAct, occurredAt: Date) {
        iconView.image = UIImage(systemName: act.systemImageName)
        iconView.tintColor = act.tintColor
        label.text = "\(act.displayName) · \(occurredAt.activityRelativeString)"
    }

    // MARK: Private

    private func setup() {
        let stack = UIStackView(arrangedSubviews: [iconView, label])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 4
        stack.alignment = .center

        addSubview(stack)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 13),
            iconView.heightAnchor.constraint(equalToConstant: 13),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}

private extension ActivityAct {
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

private extension Date {
    var activityRelativeString: String {
        let now = Date()
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
