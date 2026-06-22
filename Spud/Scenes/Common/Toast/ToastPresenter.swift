//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Presents a transient, non-blocking "pill" toast near the bottom of a window.
///
/// Usage:
/// ```swift
/// ToastPresenter.shared.show("Couldn't vote", in: window)
/// ```
///
/// Behaviour:
/// - Animates in with a fade and a slight upward translation.
/// - Dwells for ~2 seconds then animates out and removes itself.
/// - Non-blocking: the toast view has `isUserInteractionEnabled = false` so
///   touches pass through to the UI beneath it.
/// - Coalescing: calling `show` while a toast is already visible replaces its
///   text and resets the dismiss timer instead of stacking.
@MainActor
final class ToastPresenter {
    static let shared = ToastPresenter()

    private init() { }

    // MARK: - State

    private weak var currentToast: ToastView?
    private var dismissTask: Task<Void, Never>?

    // MARK: - Public

    func show(_ message: String, in window: UIWindow) {
        if let existing = currentToast {
            // Coalesce: update text and reset the dismiss timer.
            existing.messageLabel.text = message
            scheduleDismiss(for: existing)
            return
        }

        let toast = ToastView(message: message)
        toast.translatesAutoresizingMaskIntoConstraints = false
        toast.alpha = 0
        toast.transform = CGAffineTransform(translationX: 0, y: 12)
        window.addSubview(toast)

        let safeBottom = window.safeAreaInsets.bottom
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            toast.bottomAnchor.constraint(
                equalTo: window.bottomAnchor,
                constant: -(safeBottom + 24)
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

        UIView.animate(withDuration: 0.22, delay: 0, options: .curveEaseOut) {
            toast.alpha = 1
            toast.transform = .identity
        }

        scheduleDismiss(for: toast)
    }

    // MARK: - Private

    private func scheduleDismiss(for toast: ToastView) {
        dismissTask?.cancel()
        dismissTask = Task { [weak toast] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let toast else { return }
            UIView.animate(withDuration: 0.22, delay: 0, options: .curveEaseIn) {
                toast.alpha = 0
                toast.transform = CGAffineTransform(translationX: 0, y: 8)
            } completion: { _ in
                toast.removeFromSuperview()
            }
        }
    }
}

// MARK: - ToastView

private final class ToastView: UIView {
    let messageLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        return label
    }()

    init(message: String) {
        super.init(frame: .zero)
        messageLabel.text = message
        isUserInteractionEnabled = false
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 20
        layer.cornerCurve = .continuous

        addSubview(messageLabel)
        NSLayoutConstraint.activate([
            messageLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            messageLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
