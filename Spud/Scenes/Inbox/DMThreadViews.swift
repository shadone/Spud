//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUIKit
import UIKit

/// A single chat bubble. Outgoing messages align right with an accent fill;
/// incoming messages align left with a neutral fill. An optimistic (outbound)
/// bubble carries a sending/failed state: `.sending` dims the bubble and shows a
/// "Sending…" status line; `.failed` shows a red "Not delivered — tap to retry"
/// line and makes the whole row a tap target for the Retry / Discard sheet.
final class DMBubbleCell: UITableViewCell {
    static let reuseIdentifier = "DMBubbleCell"

    /// Set when the cell renders a failed optimistic bubble — the host wires this
    /// to present the Retry / Discard action sheet on a tap. nil otherwise (a
    /// sending or confirmed bubble ignores taps).
    var onFailedTap: (() -> Void)?

    private let bubble: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 16
        return view
    }()

    private let messageLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    /// The "Sending…" / "Not delivered — tap to retry" line under the bubble.
    /// Hidden for a confirmed (delivered) message.
    private let statusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .caption2)
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .right
        label.isHidden = true
        return label
    }()

    /// Wraps the bubble + status line so the whole stack aligns left/right as one.
    private let column: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .trailing
        stack.spacing = 2
        return stack
    }()

    private var leadingConstraint: NSLayoutConstraint!
    private var trailingConstraint: NSLayoutConstraint!
    private lazy var tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        bubble.addSubview(messageLabel)
        column.addArrangedSubview(bubble)
        column.addArrangedSubview(statusLabel)
        contentView.addSubview(column)

        tapRecognizer.isEnabled = false
        contentView.addGestureRecognizer(tapRecognizer)

        leadingConstraint = column.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12)
        trailingConstraint = column.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12)

        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            column.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            column.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.78),

            messageLabel.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 10),
            messageLabel.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -10),
            messageLabel.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 14),
            messageLabel.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -14),
        ])

        isAccessibilityElement = true
        accessibilityTraits = .staticText
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onFailedTap = nil
        tapRecognizer.isEnabled = false
        statusLabel.isHidden = true
        bubble.alpha = 1
        accessibilityTraits = .staticText
    }

    /// Render `item`. A confirmed bubble shows the message and no status; an
    /// optimistic one layers the sending/failed affordance on top.
    func configure(with item: DMBubbleItem) {
        messageLabel.text = item.content

        if item.isOutgoing {
            bubble.backgroundColor = .tintColor
            messageLabel.textColor = .white
            column.alignment = .trailing
            statusLabel.textAlignment = .right
            leadingConstraint.isActive = false
            trailingConstraint.isActive = true
        } else {
            bubble.backgroundColor = .secondarySystemBackground
            messageLabel.textColor = .label
            column.alignment = .leading
            statusLabel.textAlignment = .left
            trailingConstraint.isActive = false
            leadingConstraint.isActive = true
        }

        switch item.pendingStatus {
        case .none:
            bubble.alpha = 1
            statusLabel.isHidden = true
            tapRecognizer.isEnabled = false
            accessibilityTraits = .staticText
            // Direction conveyed for VoiceOver since alignment/color won't be.
            let direction = item.isOutgoing
                ? NSLocalizedString("Sent", comment: "VoiceOver: an outgoing delivered DM")
                : NSLocalizedString("Received", comment: "VoiceOver: an incoming DM")
            accessibilityLabel = "\(direction). \(item.content)"
            accessibilityValue = nil

        case .sending:
            // Dimmed + a subtle status line, consistent with the pending-comment
            // styling. Not interactive (a send in flight ignores taps).
            bubble.alpha = 0.6
            statusLabel.isHidden = false
            statusLabel.textColor = .secondaryLabel
            statusLabel.text = NSLocalizedString("Sending\u{2026}", comment: "DM bubble status: sending")
            tapRecognizer.isEnabled = false
            accessibilityTraits = .staticText
            accessibilityLabel = item.content
            // Status conveyed via value, not color alone.
            accessibilityValue = NSLocalizedString("Sending", comment: "VoiceOver value: DM is sending")

        case .failed:
            bubble.alpha = 1
            statusLabel.isHidden = false
            statusLabel.textColor = .systemRed
            statusLabel.text = NSLocalizedString(
                "Not delivered \u{2014} tap to retry",
                comment: "DM bubble status: failed to send"
            )
            tapRecognizer.isEnabled = true
            // The whole row is the tap target for Retry / Discard.
            accessibilityTraits = .button
            accessibilityLabel = item.content
            accessibilityValue = NSLocalizedString(
                "Not delivered. Double tap to retry or discard.",
                comment: "VoiceOver value: DM failed to send"
            )
        }
    }

    @objc
    private func handleTap() {
        onFailedTap?()
    }
}

/// The inline compose bar pinned above the keyboard in a DM thread. A growing
/// text view plus a circular send button.
final class DMInputBar: UIView {
    var sendTapped: ((String) -> Void)?

    private let textView: UITextView = {
        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .secondarySystemBackground
        textView.layer.cornerRadius = 18
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        textView.isScrollEnabled = false
        return textView
    }()

    private let placeholderLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = NSLocalizedString("Message", comment: "DM compose placeholder")
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .placeholderText
        return label
    }()

    private let sendButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "arrow.up.circle.fill"), for: .normal)
        button.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 30, weight: .regular),
            forImageIn: .normal
        )
        button.isEnabled = false
        return button
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        autoresizingMask = .flexibleHeight
        backgroundColor = Theme.background

        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator

        textView.delegate = self
        sendButton.addTarget(self, action: #selector(sendButtonTapped), for: .touchUpInside)

        addSubview(separator)
        addSubview(textView)
        addSubview(placeholderLabel)
        addSubview(sendButton)

        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),

            textView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            textView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -8),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),

            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 14),
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 8),

            sendButton.leadingAnchor.constraint(equalTo: textView.trailingAnchor, constant: 8),
            sendButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            sendButton.bottomAnchor.constraint(equalTo: textView.bottomAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 34),
            sendButton.heightAnchor.constraint(equalToConstant: 34),
        ])

        sendButton.accessibilityLabel = NSLocalizedString(
            "Send message",
            comment: "DM compose send-button accessibility label"
        )
        textView.accessibilityLabel = NSLocalizedString(
            "Message",
            comment: "DM compose text-field accessibility label"
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        .zero
    }

    /// Fires on every edit with the *raw* (untrimmed) text, so the host can
    /// autosave the in-progress draft.
    var textChanged: ((String) -> Void)?

    func clear() {
        textView.text = ""
        updateState()
    }

    /// Restores previously-saved draft text (e.g. on thread re-open). Does not
    /// fire `textChanged`, so restoring doesn't trigger a redundant autosave.
    func setText(_ text: String) {
        textView.text = text
        updateState()
        invalidateIntrinsicContentSize()
    }

    /// Whether the compose field currently holds no text. Used to avoid letting a
    /// late-arriving draft restore clobber characters the user already started
    /// typing before the async load completed.
    var isEmpty: Bool {
        textView.text.isEmpty
    }

    private var trimmedText: String {
        textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func updateState() {
        placeholderLabel.isHidden = !textView.text.isEmpty
        sendButton.isEnabled = !trimmedText.isEmpty
    }

    @objc
    private func sendButtonTapped() {
        let text = trimmedText
        guard !text.isEmpty else { return }
        sendTapped?(text)
    }
}

extension DMInputBar: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        updateState()
        invalidateIntrinsicContentSize()
        textChanged?(textView.text)
    }
}
