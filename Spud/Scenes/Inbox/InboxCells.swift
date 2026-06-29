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

private extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: weight],
        ])
        return UIFont(descriptor: descriptor, size: 0)
    }
}
