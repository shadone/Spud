//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Down
import SpudUIKit
import SpudUtilKit
import UIKit

/// A reusable markdown editor: a `UITextView` with a formatting-toolbar
/// `inputAccessoryView`, plus a "Write / Preview" mode swap that renders the
/// draft through `Down` into a `LinkLabel`. The preview uses the plain
/// `DownStyler` (no inline images); post and comment bodies render through
/// `BodyImageStyler` into a `BodyTextView` instead.
///
/// The view owns no drafting state of its own beyond the live `text`; toggling
/// to preview and back keeps the draft intact. Callers observe edits via
/// `onTextChange` and read/write `text`.
final class MarkdownEditorView: UIView {
    /// Display mode. `write` shows the editable text view; `preview` shows the
    /// rendered markdown.
    enum Mode {
        case write
        case preview
    }

    /// Invoked whenever the user edits the text (write mode only).
    var onTextChange: ((String) -> Void)?

    /// Invoked when a link in the rendered preview is tapped.
    var onPreviewLinkTapped: ((URL) -> Void)?

    /// Placeholder shown when the editor is empty in write mode.
    var placeholder: String? {
        didSet { placeholderLabel.text = placeholder }
    }

    private(set) var mode: Mode = .write

    var text: String {
        get { textView.text ?? "" }
        set {
            textView.text = newValue
            updatePlaceholderVisibility()
        }
    }

    /// Exposed so callers can configure border/insets/scroll and manage first
    /// responder (e.g. `becomeFirstResponder`) directly.
    let textView: UITextView

    private let toolbar = MarkdownToolbar()

    private lazy var placeholderLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .placeholderText
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var previewScrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.isHidden = true
        scrollView.alwaysBounceVertical = true
        return scrollView
    }()

    private lazy var previewLabel: LinkLabel = {
        let label = LinkLabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.tapped = { [weak self] url in
            self?.onPreviewLinkTapped?(url)
        }
        return label
    }()

    private lazy var previewEmptyLabel: UILabel = {
        let label = UILabel()
        label.text = NSLocalizedString("Nothing to preview", comment: "Shown in the markdown preview when the draft is empty")
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()

    /// Per-screen markdown styling, taken from the same configuration the post
    /// detail uses, so the preview matches the rendered result exactly.
    private let stylerConfiguration: DownStylerConfiguration

    init(textSizeAdjustment: CGFloat = 0) {
        stylerConfiguration = PostDetailAppearance.bodyStylerConfiguration(for: textSizeAdjustment)
        textView = UITextView()

        super.init(frame: .zero)

        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        textView.delegate = self
        textView.inputAccessoryView = toolbar

        toolbar.onAction = { [weak self] action in
            self?.applyFormatting(action)
        }

        addSubview(textView)
        textView.addSubview(placeholderLabel)
        addSubview(previewScrollView)
        previewScrollView.addSubview(previewLabel)
        addSubview(previewEmptyLabel)

        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),

            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: textView.textContainerInset.top),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: textView.textContainerInset.left + 5),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: textView.trailingAnchor, constant: -8),

            previewScrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            previewScrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            previewScrollView.topAnchor.constraint(equalTo: topAnchor),
            previewScrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            previewLabel.leadingAnchor.constraint(equalTo: previewScrollView.contentLayoutGuide.leadingAnchor, constant: 12),
            previewLabel.trailingAnchor.constraint(equalTo: previewScrollView.contentLayoutGuide.trailingAnchor, constant: -12),
            previewLabel.topAnchor.constraint(equalTo: previewScrollView.contentLayoutGuide.topAnchor, constant: 12),
            previewLabel.bottomAnchor.constraint(equalTo: previewScrollView.contentLayoutGuide.bottomAnchor, constant: -12),
            previewLabel.widthAnchor.constraint(equalTo: previewScrollView.frameLayoutGuide.widthAnchor, constant: -24),

            previewEmptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            previewEmptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            previewEmptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            previewEmptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
        ])
    }

    // MARK: Mode

    /// Switches between write and preview. Re-renders the markdown when
    /// entering preview; the draft text is never mutated.
    func setMode(_ newMode: Mode) {
        guard newMode != mode else { return }
        mode = newMode

        switch newMode {
        case .write:
            previewScrollView.isHidden = true
            previewEmptyLabel.isHidden = true
            textView.isHidden = false
            updatePlaceholderVisibility()
            textView.becomeFirstResponder()

        case .preview:
            textView.resignFirstResponder()
            textView.isHidden = true
            placeholderLabel.isHidden = true
            renderPreview()
            previewScrollView.isHidden = false
        }
    }

    private func renderPreview() {
        let markdown = text
        guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            previewLabel.attributedText = nil
            previewEmptyLabel.isHidden = false
            return
        }
        previewEmptyLabel.isHidden = true
        previewLabel.attributedText = Down(markdownString: markdown)
            .toAttributedString(styler: DownStyler(configuration: stylerConfiguration))
            .addingAutolinks()
    }

    // MARK: Formatting

    /// Bridges the current `UITextView` selection to the pure
    /// `MarkdownFormatting` transforms and applies the resulting text +
    /// selection back to the text view, then notifies `onTextChange`.
    private func applyFormatting(_ action: MarkdownFormatting.Action) {
        let current = textView.text ?? ""
        guard let selectedRange = textView.selectedTextRange else { return }

        // Convert the UITextView selection (UITextPosition) to a Swift
        // String.Index range over the current text.
        let nsRange = NSRange(
            location: textView.offset(from: textView.beginningOfDocument, to: selectedRange.start),
            length: textView.offset(from: selectedRange.start, to: selectedRange.end)
        )
        guard let stringRange = Range(nsRange, in: current) else { return }

        let edit = MarkdownFormatting.apply(action, to: current, selection: stringRange)

        textView.text = edit.text
        Haptics.tap()

        // Restore the selection the transform asked for.
        let newNSRange = NSRange(edit.selectedRange, in: edit.text)
        if
            let start = textView.position(from: textView.beginningOfDocument, offset: newNSRange.location),
            let end = textView.position(from: start, offset: newNSRange.length)
        {
            textView.selectedTextRange = textView.textRange(from: start, to: end)
        }

        updatePlaceholderVisibility()
        onTextChange?(edit.text)
    }

    // MARK: Placeholder

    private func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = !(textView.text ?? "").isEmpty || mode == .preview
    }
}

// MARK: - UITextViewDelegate

extension MarkdownEditorView: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        updatePlaceholderVisibility()
        onTextChange?(textView.text ?? "")
    }
}
