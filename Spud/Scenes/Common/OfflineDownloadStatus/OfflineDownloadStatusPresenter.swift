//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SwiftUI
import UIKit

/// Presents the persistent, non-blocking offline-download status pill and anchors
/// it to a window, so it survives feed switches and tab switches while a download
/// runs — unlike the retired modal progress sheet, whose every dismissal cancelled
/// the download.
///
/// A window-level singleton (like ``ToastPresenter``): it hosts
/// ``OfflineDownloadStatusView`` in a `UIHostingController` and adds that
/// controller's view directly to the window, bottom-centered above the safe area.
/// The pill binds to the passed ``OfflineDownloadProgressViewModel`` (`@Observable`),
/// so the controller's drain loop updates the pill just by writing the view
/// model — the presenter is told only when to show and when to dismiss.
///
/// **Dismissing the pill never cancels the download.** Cancellation is exclusively
/// the pill's ✕, which routes back through the view model's `onCancel`. The
/// presenter is presentation-only; it knows nothing about the download engine.
@MainActor
final class OfflineDownloadStatusPresenter {
    static let shared = OfflineDownloadStatusPresenter()

    private init() { }

    // MARK: - State

    /// The hosting controller for the live pill, retained so SwiftUI keeps driving
    /// its updates (a hosting controller added to a window but not to a VC hierarchy
    /// still renders as long as something holds it). Nil when no pill is showing.
    private var hostingController: UIHostingController<OfflineDownloadStatusView>?

    /// Whether a pill is currently on screen.
    var isShowing: Bool {
        hostingController != nil
    }

    // MARK: - Public

    /// Shows the status pill for `viewModel`, anchored to `window`. Replaces any
    /// existing pill outright (there is only ever one download at a time).
    func show(viewModel: OfflineDownloadProgressViewModel, in window: UIWindow) {
        removeHost()

        let host = UIHostingController(rootView: OfflineDownloadStatusView(viewModel: viewModel))
        host.view.backgroundColor = .clear
        // Self-size height to the (Dynamic Type-dependent) content; width is pinned
        // by the constraints below.
        host.sizingOptions = .intrinsicContentSize
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.alpha = 0
        host.view.transform = CGAffineTransform(translationX: 0, y: 12)
        window.addSubview(host.view)

        // A near-full-width pill on iPhone (window minus 16pt margins), capped at
        // 460pt and centered so it reads as a tidy pill in the regular size class
        // (iPad / landscape) rather than stretching edge to edge.
        let width = host.view.widthAnchor.constraint(equalTo: window.widthAnchor, constant: -32)
        width.priority = .defaultHigh
        NSLayoutConstraint.activate([
            host.view.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            host.view.bottomAnchor.constraint(
                equalTo: window.safeAreaLayoutGuide.bottomAnchor,
                constant: -24
            ),
            width,
            host.view.widthAnchor.constraint(lessThanOrEqualToConstant: 460),
            host.view.leadingAnchor.constraint(
                greaterThanOrEqualTo: window.leadingAnchor,
                constant: 16
            ),
        ])

        hostingController = host

        UIView.animate(withDuration: 0.22, delay: 0, options: .curveEaseOut) {
            host.view.alpha = 1
            host.view.transform = .identity
        }
    }

    /// Animates the pill out (or removes it immediately when `animated` is false),
    /// invoking `completion` once it's gone. No-op — but still calls `completion` —
    /// when no pill is showing, so callers can chain a follow-up (e.g. a result
    /// toast) unconditionally.
    func dismiss(animated: Bool = true, completion: (() -> Void)? = nil) {
        guard let host = hostingController else {
            completion?()
            return
        }
        hostingController = nil

        guard animated else {
            host.view.removeFromSuperview()
            completion?()
            return
        }

        UIView.animate(withDuration: 0.22, delay: 0, options: .curveEaseIn) {
            host.view.alpha = 0
            host.view.transform = CGAffineTransform(translationX: 0, y: 8)
        } completion: { _ in
            host.view.removeFromSuperview()
            completion?()
        }
    }

    // MARK: - Private

    private func removeHost() {
        hostingController?.view.removeFromSuperview()
        hostingController = nil
    }
}
