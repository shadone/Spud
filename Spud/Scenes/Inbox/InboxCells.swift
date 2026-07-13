//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import SpudUIKit
import UIKit

/// A comment-style inbox row used for both replies and mentions. Shows the
/// author + context line, the comment body, and an unread dot when the item
/// has not been read.
final class InboxCommentCell: UITableViewCell {
    static let reuseIdentifier = "InboxCommentCell"

    private let unreadDot: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemBlue
        view.layer.cornerRadius = 4
        view.isHidden = true
        return view
    }()

    private let contextLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    private let contentLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 4
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .label
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    private let postLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessoryType = .disclosureIndicator

        let textStack = UIStackView(arrangedSubviews: [contextLabel, contentLabel, postLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 4

        contentView.addSubview(unreadDot)
        contentView.addSubview(textStack)

        NSLayoutConstraint.activate([
            unreadDot.widthAnchor.constraint(equalToConstant: 8),
            unreadDot.heightAnchor.constraint(equalToConstant: 8),
            unreadDot.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 6),
            unreadDot.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor, constant: 6),

            textStack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor, constant: 8),
            textStack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            textStack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            textStack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(creatorName: String, content: String, postTitle: String, communityName: String, isRead: Bool) {
        contextLabel.text = creatorName
        contextLabel.font = isRead
            ? .preferredFont(forTextStyle: .subheadline)
            : UIFont.preferredFont(forTextStyle: .subheadline).withWeight(.semibold)
        contentLabel.text = content
        postLabel.text = String(
            format: NSLocalizedString(
                "in %@ · %@",
                comment: "Inbox row footer: in <community> · <post title>"
            ),
            communityName,
            postTitle
        )
        unreadDot.isHidden = isRead
        backgroundColor = isRead ? nil : UIColor.systemBlue.withAlphaComponent(0.06)
    }
}

/// A conversation summary row for the Messages list.
final class InboxConversationCell: UITableViewCell {
    static let reuseIdentifier = "InboxConversationCell"

    private let avatarView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.layer.cornerRadius = 20
        view.backgroundColor = .secondarySystemFill
        view.image = UIImage(systemName: "person.crop.circle.fill")
        view.tintColor = .tertiaryLabel
        return view
    }()

    private let unreadDot: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemBlue
        view.layer.cornerRadius = 4
        view.isHidden = true
        return view
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        label.font = .preferredFont(forTextStyle: .headline)
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    private let previewLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 2
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    /// Optimistic-send indicator: "Sending…" (sending) or "Not delivered"
    /// (failed). Hidden when the conversation has no in-flight outgoing message.
    private let statusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        label.font = .preferredFont(forTextStyle: .caption1)
        label.adjustsFontForContentSizeCategory = true
        label.isHidden = true
        return label
    }()

    private var avatarTask: Task<Void, Never>?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessoryType = .disclosureIndicator

        let textStack = UIStackView(arrangedSubviews: [nameLabel, previewLabel, statusLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 2

        contentView.addSubview(unreadDot)
        contentView.addSubview(avatarView)
        contentView.addSubview(textStack)

        NSLayoutConstraint.activate([
            unreadDot.widthAnchor.constraint(equalToConstant: 8),
            unreadDot.heightAnchor.constraint(equalToConstant: 8),
            unreadDot.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 6),
            unreadDot.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            avatarView.widthAnchor.constraint(equalToConstant: 40),
            avatarView.heightAnchor.constraint(equalToConstant: 40),
            avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            avatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarView.topAnchor.constraint(greaterThanOrEqualTo: contentView.layoutMarginsGuide.topAnchor),

            textStack.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            textStack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            textStack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarTask?.cancel()
        avatarTask = nil
        avatarView.image = UIImage(systemName: "person.crop.circle.fill")
        statusLabel.isHidden = true
        statusLabel.attributedText = nil
    }

    func configure(with conversation: InboxConversation, imageService: ImageServiceType) {
        nameLabel.text = conversation.correspondentName
        previewLabel.text = conversation.latestContent
        unreadDot.isHidden = !conversation.hasUnread
        nameLabel.font = conversation.hasUnread
            ? UIFont.preferredFont(forTextStyle: .headline)
            : UIFont.preferredFont(forTextStyle: .body)

        configureStatus(conversation.pendingStatus)
        configureAccessibility(conversation)

        guard let url = conversation.correspondentAvatarUrl else { return }
        avatarTask?.cancel()
        avatarTask = Task { [weak self] in
            for await state in imageService.fetch(url) {
                if Task.isCancelled { return }
                if case let .ready(image) = state {
                    self?.avatarView.image = image
                }
            }
        }
    }

    /// Render the optimistic-send indicator as an inline SF symbol + label:
    /// "Sending…" (secondary) or "Not delivered" (red), or hidden when nothing is
    /// in flight. Color carries meaning, so the failed state also leads with the
    /// triangle glyph and the accessibility label spells it out (see
    /// `configureAccessibility`).
    private func configureStatus(_ status: InboxConversationPendingStatus?) {
        guard let status else {
            statusLabel.isHidden = true
            statusLabel.attributedText = nil
            return
        }

        let symbolName: String
        let text: String
        let color: UIColor
        switch status {
        case .sending:
            symbolName = "clock"
            text = NSLocalizedString("Sending…", comment: "Inbox conversation row: an outgoing message is in flight")
            color = .secondaryLabel
        case .failed:
            symbolName = "exclamationmark.triangle.fill"
            text = NSLocalizedString("Not delivered", comment: "Inbox conversation row: an outgoing message failed to send")
            color = .systemRed
        }

        let attachment = NSTextAttachment()
        attachment.image = UIImage(systemName: symbolName)?.withTintColor(color, renderingMode: .alwaysOriginal)
        let line = NSMutableAttributedString(attachment: attachment)
        line.append(NSAttributedString(
            string: " " + text,
            attributes: [.foregroundColor: color]
        ))
        statusLabel.attributedText = line
        statusLabel.isHidden = false
    }

    /// Compose a single VoiceOver-friendly label so the row reads as one element
    /// (name, preview, unread, and any send status) rather than fragmented
    /// sub-labels, and so the send state is conveyed without relying on color.
    private func configureAccessibility(_ conversation: InboxConversation) {
        isAccessibilityElement = true
        accessibilityTraits = .button

        var parts: [String] = [conversation.correspondentName]
        if !conversation.latestContent.isEmpty {
            parts.append(conversation.latestContent)
        }
        switch conversation.pendingStatus {
        case .sending:
            parts.append(NSLocalizedString("Sending", comment: "Inbox conversation accessibility: message sending"))
        case .failed:
            parts.append(NSLocalizedString("Not delivered", comment: "Inbox conversation accessibility: message failed"))
        case nil:
            break
        }
        if conversation.hasUnread {
            parts.append(NSLocalizedString("Unread", comment: "Inbox conversation accessibility: has unread messages"))
        }
        accessibilityLabel = parts.joined(separator: ", ")
    }
}

/// A reminder row in the Inbox "Reminders" segment: the target post's
/// thumbnail, title, and `c/<community>@<instance>` handle, plus a status
/// line whose text depends on the reminder's `kind` (`ReminderStatusText`) -
/// for a `time` reminder, a relative "in 2 days" countdown while `scheduled`,
/// or "Tap to revisit" once `fired`; for an `activity` reminder (Phase 2),
/// "Watching for new comments" while `scheduled`, or "New comments · tap to
/// catch up" once `fired`. `fired` is the same actionable state that lit the
/// tab badge until the segment was opened, for either kind. An unread-style
/// dot marks a still-unseen fired reminder, matching
/// `InboxCommentCell`/`InboxConversationCell`'s visual language for
/// "something new happened here".
final class InboxReminderCell: UITableViewCell {
    static let reuseIdentifier = "InboxReminderCell"

    private let unseenDot: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemBlue
        view.layer.cornerRadius = 4
        view.isHidden = true
        return view
    }()

    private let thumbnailView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.layer.cornerRadius = 8
        view.backgroundColor = .secondarySystemFill
        view.image = UIImage(systemName: "photo")
        view.tintColor = .tertiaryLabel
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 2
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .label
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    private let communityLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    private var thumbnailTask: Task<Void, Never>?

    private static let thumbnailSize = CGSize(width: 56, height: 56)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessoryType = .disclosureIndicator

        // A `UIStackView` (not label-to-label anchors), matching
        // `InboxCommentCell`/`InboxConversationCell`: its `intrinsicContentSize`
        // is computed directly from the arranged subviews, which is what lets
        // `systemLayoutSizeFitting` measure the column correctly even though
        // `thumbnailView` is a fixed-size sibling. An explicit label-to-label
        // anchor chain (title.bottom -> community.top, community.bottom ->
        // status.top, status.bottom == marginsGuide.bottom, all required) was
        // tried first and consistently mis-measured: with the test harness's
        // `cell.frame.height = 2000` planting a *real*, required
        // `contentView.height == 2000` constraint, the anchor chain has no
        // single authoritative size signal to fall back on, so
        // `systemLayoutSizeFitting` resolves the resulting required/required
        // conflict by silently stretching `statusLabel` to ~1900pt instead of
        // shrinking `contentView` - clipping the status line out of the
        // rendered cell entirely. The stack view doesn't hit this because its
        // own intrinsic-size override is authoritative regardless.
        let textStack = UIStackView(arrangedSubviews: [titleLabel, communityLabel, statusLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 2

        contentView.addSubview(unseenDot)
        contentView.addSubview(thumbnailView)
        contentView.addSubview(textStack)

        NSLayoutConstraint.activate([
            unseenDot.widthAnchor.constraint(equalToConstant: 8),
            unseenDot.heightAnchor.constraint(equalToConstant: 8),
            unseenDot.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 6),
            unseenDot.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor, constant: 6),

            thumbnailView.widthAnchor.constraint(equalToConstant: Self.thumbnailSize.width),
            thumbnailView.heightAnchor.constraint(equalToConstant: Self.thumbnailSize.height),
            thumbnailView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            thumbnailView.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            thumbnailView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.layoutMarginsGuide.bottomAnchor),

            textStack.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            textStack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            textStack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// `titleLabel.numberOfLines == 2`'s intrinsic height is only correct once
    /// `preferredMaxLayoutWidth` matches its real constrained width: a
    /// multi-line `UILabel`'s `intrinsicContentSize` reports the UNWRAPPED
    /// (single-line) size unless something has told it what width to wrap at,
    /// and `systemLayoutSizeFitting` (the snapshot tests' - and any
    /// self-sizing table view's - cell-height measurement idiom) does not
    /// reliably feed a solved constraint width back into that property before
    /// reading intrinsic size. Left unset, a title whose text straddles the
    /// 1-vs-2-line boundary measures as 1 line (undercounting the row's real
    /// height) while the subsequent real layout pass still wraps it to 2,
    /// silently squeezing `statusLabel` out of the rendered cell.
    override func layoutSubviews() {
        super.layoutSubviews()
        titleLabel.preferredMaxLayoutWidth = titleLabel.bounds.width
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailTask?.cancel()
        thumbnailTask = nil
        thumbnailView.image = UIImage(systemName: "photo")
    }

    func configure(with reminder: ReminderListRow, imageService: ImageServiceType) {
        titleLabel.text = reminder.titleSnapshot
        communityLabel.text = "c/\(reminder.communityName)@\(reminder.instanceHost)"
        unseenDot.isHidden = !reminder.unseen

        let status = ReminderStatusText.describe(for: reminder)
        statusLabel.text = status
        let isFired = reminder.status == ReminderRecord.Status.fired.rawValue
        statusLabel.textColor = isFired ? .systemBlue : .secondaryLabel
        statusLabel.font = isFired
            ? UIFont.preferredFont(forTextStyle: .subheadline).withWeight(.semibold)
            : .preferredFont(forTextStyle: .subheadline)

        isAccessibilityElement = true
        accessibilityTraits = .button
        var label = String(
            format: NSLocalizedString(
                "Reminder: %@, %@",
                comment: "Inbox reminder row accessibility label; first %@ is the post title, second %@ is the status (e.g. \"in 2 days\" or \"Tap to revisit\")"
            ),
            reminder.titleSnapshot,
            status
        )
        // Mirrors InboxCommentCell/InboxConversationCell's unread dot: convey
        // the blue unseen dot as text so VoiceOver users get the same "something
        // new happened here" signal as sighted users.
        if reminder.unseen {
            label += ", " + NSLocalizedString("New", comment: "Inbox reminder row accessibility: the reminder is unseen")
        }
        accessibilityLabel = label

        thumbnailTask?.cancel()
        guard let urlString = reminder.thumbnailUrl, let url = URL(string: urlString) else { return }
        thumbnailTask = Task { [weak self] in
            for await state in imageService.fetch(url, downsampleTo: Self.thumbnailSize) {
                if Task.isCancelled { return }
                if case let .ready(image) = state {
                    self?.thumbnailView.image = image
                }
            }
        }
    }
}

private extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: weight],
        ])
        return UIFont(descriptor: descriptor, size: 0)
    }
}
