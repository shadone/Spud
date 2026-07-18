//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudUIKit
import UIKit

/// A small sheet for editing the alt text that travels with the exported image.
/// It opens prefilled with the current description (the user's override, or the
/// auto-generated text when none is set) and offers an "Auto" button that
/// restores the auto text. The override is per-card and never persisted — the
/// editor discards it when a different post/comment is shared.
///
/// On Done it reports the result back via ``onSave``: `nil` means "use auto
/// text", any other string is the user's override.
final class ShareAsImageAltTextViewController: UIViewController {
    /// Called on Done with the chosen alt text: `nil` = auto, else the override.
    var onSave: ((String?) -> Void)?

    private let autoText: String
    private var isAuto: Bool
    private let textView = UITextView()
    private let footnoteLabel = UILabel()
    private lazy var autoButton = UIBarButtonItem(
        title: "Auto",
        style: .plain,
        target: self,
        action: #selector(restoreAuto)
    )

    /// - Parameters:
    ///   - currentText: the text to prefill (override or auto).
    ///   - isAuto: whether `currentText` is the auto-generated text.
    ///   - autoText: the auto-generated text the "Auto" button restores.
    init(currentText: String, isAuto: Bool, autoText: String) {
        self.autoText = autoText
        self.isAuto = isAuto
        super.init(nibName: nil, bundle: nil)
        textView.text = currentText
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Alt Text"

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancel)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(done)
        )

        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.isScrollEnabled = true
        textView.delegate = self
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        textView.layer.cornerRadius = 12
        textView.layer.cornerCurve = .continuous
        textView.backgroundColor = .secondarySystemBackground
        textView.accessibilityLabel = "Image description"
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textView)

        footnoteLabel.text = "Describes the image for people using VoiceOver. " +
            "Tap Auto to regenerate it from the post."
        footnoteLabel.font = .preferredFont(forTextStyle: .footnote)
        footnoteLabel.adjustsFontForContentSizeCategory = true
        footnoteLabel.textColor = .secondaryLabel
        footnoteLabel.numberOfLines = 0
        footnoteLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(footnoteLabel)

        let margins = view.layoutMarginsGuide
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            textView.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: margins.trailingAnchor),

            footnoteLabel.topAnchor.constraint(equalTo: textView.bottomAnchor, constant: 12),
            footnoteLabel.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            footnoteLabel.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            footnoteLabel.bottomAnchor.constraint(
                lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -16
            ),
        ])

        // The auto button is presented in the toolbar area of the nav item so it
        // sits distinctly from Cancel/Done.
        navigationItem.rightBarButtonItems = [navigationItem.rightBarButtonItem!, autoButton]
        updateAutoButtonState()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        textView.becomeFirstResponder()
    }

    private func updateAutoButtonState() {
        // Disable "Auto" when already showing auto text — there's nothing to
        // restore.
        autoButton.isEnabled = !isAuto
    }

    @objc
    private func restoreAuto() {
        isAuto = true
        textView.text = autoText
        updateAutoButtonState()
        Haptics.tap()
    }

    @objc
    private func cancel() {
        dismiss(animated: true)
    }

    @objc
    private func done() {
        onSave?(isAuto ? nil : textView.text)
        dismiss(animated: true)
    }
}

extension ShareAsImageAltTextViewController: UITextViewDelegate {
    func textViewDidChange(_: UITextView) {
        // Any manual edit means the text is no longer the auto text.
        if isAuto {
            isAuto = false
            updateAutoButtonState()
        }
    }
}
