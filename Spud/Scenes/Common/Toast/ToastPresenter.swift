//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudUIKit
import UIKit

/// Presents a transient, non-blocking "pill" toast near the bottom of a window.
///
/// Two forms:
/// - Plain text (`show(_:in:)`): non-interactive, ~2s, coalesces by updating the
///   text of an existing plain toast and resetting its timer.
/// - Interactive (`show(_:actionTitle:in:duration:action:)`): adds a trailing
///   accent action button (e.g. "Undo"); the pill is content-sized, so only it
///   intercepts touches - the rest of the screen stays usable. Replaces any
///   existing toast rather than coalescing. Tapping the action button runs
///   `action` directly; if `action` presents a follow-up toast (as the undo
///   flow does), the hint is replaced by it and dwells its full duration.
///
/// `dismiss()` animates the current toast out immediately.
@MainActor
final class ToastPresenter {
    static let shared = ToastPresenter()

    private init() { }

    // MARK: - State

    private weak var currentToast: ToastView?
    private var dismissTask: Task<Void, Never>?

    // MARK: - Public

    func show(_ message: String, in window: UIWindow) {
        // Spud presents toasts in a single window, so coalescing an existing
        // plain toast reuses it in place; the `window` argument is only needed
        // when presenting a fresh toast below.
        if let existing = currentToast, !existing.isInteractive {
            existing.messageLabel.text = message
            scheduleDismiss(for: existing, after: .seconds(2))
            return
        }
        present(ToastView(message: message), in: window, duration: .seconds(2))
    }

    func show(
        _ message: String,
        actionTitle: String,
        in window: UIWindow,
        duration: Duration = .seconds(4),
        action: @escaping @MainActor () -> Void
    ) {
        let toast = ToastView(message: message, actionTitle: actionTitle, action: action)
        present(toast, in: window, duration: duration)
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        guard let toast = currentToast else { return }
        currentToast = nil
        animateOut(toast)
    }

    // MARK: - Private

    private func present(_ toast: ToastView, in window: UIWindow, duration: Duration) {
        // Replace any existing toast outright (covers plain <-> interactive swaps).
        if let existing = currentToast {
            dismissTask?.cancel()
            dismissTask = nil
            existing.removeFromSuperview()
            currentToast = nil
        }

        toast.translatesAutoresizingMaskIntoConstraints = false
        toast.alpha = 0
        toast.transform = CGAffineTransform(translationX: 0, y: 12)
        window.addSubview(toast)

        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            toast.bottomAnchor.constraint(
                equalTo: window.safeAreaLayoutGuide.bottomAnchor,
                constant: -24
            ),
            toast.leadingAnchor.constraint(
                greaterThanOrEqualTo: window.leadingAnchor,
                constant: 16
            ),
            toast.trailingAnchor.constraint(
                lessThanOrEqualTo: window.trailingAnchor,
                constant: -16
            ),
        ])

        currentToast = toast

        guard !UIAccessibility.isReduceMotionEnabled else {
            toast.alpha = 1
            toast.transform = .identity
            scheduleDismiss(for: toast, after: duration)
            return
        }

        UIView.animate(withDuration: 0.22, delay: 0, options: .curveEaseOut) {
            toast.alpha = 1
            toast.transform = .identity
        }

        scheduleDismiss(for: toast, after: duration)
    }

    private func scheduleDismiss(for toast: ToastView, after duration: Duration) {
        dismissTask?.cancel()
        dismissTask = Task { [weak self, weak toast] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self, let toast else { return }
            currentToast = nil
            dismissTask = nil
            animateOut(toast)
        }
    }

    private func animateOut(_ toast: ToastView) {
        guard !UIAccessibility.isReduceMotionEnabled else {
            toast.removeFromSuperview()
            return
        }
        UIView.animate(withDuration: 0.22, delay: 0, options: .curveEaseIn) {
            toast.alpha = 0
            toast.transform = CGAffineTransform(translationX: 0, y: 8)
        } completion: { _ in
            toast.removeFromSuperview()
        }
    }
}

// MARK: - ToastView

final class ToastView: UIView {
    let messageLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        return label
    }()

    /// The pill's Liquid Glass surface. `self` is just a plain layout
    /// container (sized/positioned by `ToastPresenter`); all visible chrome
    /// (material, corner radius, clipping) lives on this nested
    /// `UIVisualEffectView` — the same architecture `LowResPreviewPillView`
    /// uses for its own floating pill.
    private let glassView: UIVisualEffectView = {
        let view = UIVisualEffectView(effect: GlassTokens.controlSurface)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 20
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true
        return view
    }()

    /// True when the toast hosts an action button (and is interactive).
    let isInteractive: Bool

    init(
        message: String,
        actionTitle: String? = nil,
        action: (@MainActor () -> Void)? = nil
    ) {
        isInteractive = actionTitle != nil && action != nil
        super.init(frame: .zero)
        messageLabel.text = message

        addSubview(glassView)
        NSLayoutConstraint.activate([
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassView.topAnchor.constraint(equalTo: topAnchor),
            glassView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // The flat `secondarySystemBackground` fill, hand-rolled CALayer
        // shadow, and hairline border this pill used before Liquid Glass are
        // gone: `glassView`'s own material now supplies both the surface and
        // its elevation (a real glass surface already renders a
        // specular/depth cue — stacking a flat drop shadow and a hard-edge
        // stroke underneath it would double up and read as mismatched,
        // dated chrome, the same reasoning Task 15 applied when it dropped
        // the media-viewer jump button's CALayer shadow).

        if let actionTitle, let action {
            isUserInteractionEnabled = true
            messageLabel.textAlignment = .natural

            var config = UIButton.Configuration.plain()
            config.title = actionTitle
            // Accent-coloured text on the toast's glass surface, so the
            // content variant rather than the fill accent.
            config.baseForegroundColor = ThemeManager.currentContentAccentColor
            let button = UIButton(configuration: config)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.setContentHuggingPriority(.required, for: .horizontal)
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            button.addAction(UIAction { _ in action() }, for: .touchUpInside)

            let stack = UIStackView(arrangedSubviews: [messageLabel, button])
            stack.translatesAutoresizingMaskIntoConstraints = false
            stack.axis = .horizontal
            stack.alignment = .center
            stack.spacing = 12
            glassView.contentView.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: glassView.contentView.topAnchor, constant: 8),
                stack.bottomAnchor.constraint(equalTo: glassView.contentView.bottomAnchor, constant: -8),
                stack.leadingAnchor.constraint(equalTo: glassView.contentView.leadingAnchor, constant: 16),
                stack.trailingAnchor.constraint(equalTo: glassView.contentView.trailingAnchor, constant: -12),
            ])
        } else {
            isUserInteractionEnabled = false
            messageLabel.textAlignment = .center
            glassView.contentView.addSubview(messageLabel)
            NSLayoutConstraint.activate([
                messageLabel.topAnchor.constraint(equalTo: glassView.contentView.topAnchor, constant: 10),
                messageLabel.bottomAnchor.constraint(equalTo: glassView.contentView.bottomAnchor, constant: -10),
                messageLabel.leadingAnchor.constraint(equalTo: glassView.contentView.leadingAnchor, constant: 16),
                messageLabel.trailingAnchor.constraint(equalTo: glassView.contentView.trailingAnchor, constant: -16),
            ])
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
