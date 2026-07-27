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
    /// The shortest the editing card is allowed to get. Reached only in the
    /// worst case — a medium detent whose remaining space, once the keyboard is
    /// up, is smaller than card + hint. Roughly four body lines inside the card's
    /// 12pt insets: enough to keep editing meaningful.
    static let minimumCardHeight: CGFloat = 120

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

        installLayout()

        // "Auto" is a second right bar button, sitting next to Done (and
        // distinctly from Cancel on the left). Both are text-labeled, so a
        // fixed space keeps "Done" and "Auto" from visually running together
        // (HIG: keep text-labeled toolbar actions separated).
        navigationItem.rightBarButtonItems = [
            navigationItem.rightBarButtonItem!,
            .fixedSpace(12),
            autoButton,
        ]
        updateAutoButtonState()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        textView.becomeFirstResponder()
    }

    /// Pins the editing card between the top of the sheet and the top of the
    /// keyboard, so it fills whatever height the sheet currently has.
    ///
    /// The bottom pin is the load-bearing part. `textView` scrolls, and a
    /// scrolling `UITextView` reports no intrinsic content height, so its height
    /// is a free variable that only the constraint chain can fix. Leaving the
    /// bottom end open — an inequality, or no bottom constraint at all — leaves
    /// that variable under-determined and Auto Layout resolves it to ZERO: the
    /// sheet then renders as nothing but the grey hint, with no build warning
    /// and no runtime complaint. That shipped. `ShareAsImageAltTextLayoutTests`
    /// measures the card so it cannot ship again.
    ///
    /// It pins to `keyboardLayoutGuide` rather than the safe area because the
    /// sheet raises the keyboard immediately (`viewDidAppear`), and the guide
    /// falls back to the bottom safe area when the keyboard is down — one
    /// constraint covers both states. Same convention as `ComposerViewController`
    /// and `NewPostViewController`.
    ///
    /// Priorities: the card's minimum height is REQUIRED and the fill pin yields
    /// (`.defaultHigh`), never the other way round. Nothing else required
    /// constrains the bottom end, so the required subset is always satisfiable —
    /// a required floor here cannot produce a conflict. In the one case where
    /// both cannot hold (a medium detent with the keyboard up leaving less than
    /// card + hint), the hint slides under the keyboard and the card stays
    /// usable, which is the right way round for a static piece of help text.
    private func installLayout() {
        // The hint keeps its full height; the fill pin is what gives.
        footnoteLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        let fillsAvailableHeight = footnoteLabel.bottomAnchor.constraint(
            equalTo: view.keyboardLayoutGuide.topAnchor,
            constant: -16
        )
        fillsAvailableHeight.priority = .defaultHigh

        let margins = view.layoutMarginsGuide
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            textView.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: Self.minimumCardHeight),

            footnoteLabel.topAnchor.constraint(equalTo: textView.bottomAnchor, constant: 12),
            footnoteLabel.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            footnoteLabel.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            fillsAvailableHeight,
        ])
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
