//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import Testing
import UIKit
@testable import Spud

/// Covers the non-blocking pill's presenter: showing/dismissing it tracks
/// `isShowing`, and — the crux of the QoL change — **dismissing the pill does not
/// cancel the download**. The only cancel path is the view model's `onCancel`
/// (wired to the pill's ✕), never a dismissal.
///
/// Serialized because `OfflineDownloadStatusPresenter.shared` is a process-global
/// singleton; the `@MainActor` requirement already serializes on the main actor,
/// and the explicit `.serialized` documents the shared-state intent.
@MainActor
@Suite(.serialized)
struct OfflineDownloadStatusPresenterTests {
    /// A window to anchor the pill to. Off-screen is fine for these state checks.
    private func makeWindow() -> UIWindow {
        UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    }

    @Test
    func showThenDismissTracksIsShowing() {
        let presenter = OfflineDownloadStatusPresenter.shared
        presenter.dismiss(animated: false)
        #expect(presenter.isShowing == false)

        let vm = OfflineDownloadProgressViewModel(onCancel: { })
        presenter.show(viewModel: vm, in: makeWindow())
        #expect(presenter.isShowing == true)

        presenter.dismiss(animated: false)
        #expect(presenter.isShowing == false)
    }

    @Test
    func dismissingThePillDoesNotCancelTheDownload() {
        let presenter = OfflineDownloadStatusPresenter.shared
        presenter.dismiss(animated: false)

        var cancelled = false
        let vm = OfflineDownloadProgressViewModel(onCancel: { cancelled = true })

        presenter.show(viewModel: vm, in: makeWindow())
        // Dismissing the pill must NOT trigger the cancel closure — a swipe/dismiss
        // no longer tears down the run (unlike the retired modal sheet).
        presenter.dismiss(animated: false)
        #expect(cancelled == false)

        // The ✕ — i.e. invoking the view model's onCancel — is the sole cancel path.
        vm.onCancel()
        #expect(cancelled == true)
    }

    @Test
    func showReplacesAnExistingPill() {
        let presenter = OfflineDownloadStatusPresenter.shared
        presenter.dismiss(animated: false)

        let first = OfflineDownloadProgressViewModel(onCancel: { })
        presenter.show(viewModel: first, in: makeWindow())
        #expect(presenter.isShowing == true)

        // A second show replaces the first outright (there is only ever one
        // download at a time) and leaves the pill showing.
        let second = OfflineDownloadProgressViewModel(onCancel: { })
        presenter.show(viewModel: second, in: makeWindow())
        #expect(presenter.isShowing == true)

        presenter.dismiss(animated: false)
        #expect(presenter.isShowing == false)
    }
}
