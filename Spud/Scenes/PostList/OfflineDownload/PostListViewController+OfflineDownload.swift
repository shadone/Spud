//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SpudDataKit
import SpudUIKit
import SpudUtilKit
import SwiftUI
import UIKit

/// Offline-download launch + lifecycle, hosted on `PostListViewController`.
///
/// Flow: the Quick Switch popover's "Download for offline" action calls
/// ``startOfflineDownload()``, which (after the offline / in-flight guards)
/// presents a small chooser letting the user pick how many posts to save. On
/// Download the chooser dismisses and ``beginOfflineDownload(maxPosts:archiveLinks:)``
/// runs: it resolves the current feed's account/site identifiers and the
/// comment-sort + show-NSFW preferences, shows a **non-blocking status pill**
/// (``OfflineDownloadStatusPresenter``), and drains the service's `AsyncStream`
/// on the main actor — pushing each value into the pill's view model. On
/// `.finished` / `.failed` / `.cancelled` it dismisses the pill and shows a toast.
///
/// **Dismissing the pill does NOT cancel the download.** The download runs in the
/// service's retained work task, independent of the pill; the pill is anchored to
/// the window (not this controller's view), so it survives feed switches and tab
/// switches. Cancellation is exclusively the pill's ✕, which routes to
/// ``cancelOfflineDownload()`` — that asks the service to cancel while the drain
/// task keeps reading until the terminal `.cancelled` lands (so the cancelled
/// state is observably rendered). The drain task is also torn down in the
/// controller's `deinit`, which cancels the run and removes the pill.
extension PostListViewController {
    /// Presents the "Download for offline" chooser (post-count picker) for the
    /// current feed. No-ops (with a brief toast) when offline, when a download is
    /// already running, or when the feed's account can't be resolved — the same
    /// guards the actual download applies, checked up front so the chooser never
    /// appears over a doomed run.
    func startOfflineDownload() {
        // Don't start a second download over a live one — the actor would reject
        // it anyway, but bailing here keeps the existing pill's run intact.
        guard offlineDownloadTask == nil else { return }

        // You can't predownload without a connection. Surface a brief toast
        // rather than opening a chooser whose download would immediately fail.
        guard reachabilityMonitor.isOnline else {
            if let window = offlineDownloadWindow {
                ToastPresenter.shared.show(
                    NSLocalizedString(
                        "You're offline",
                        comment: "Toast shown when trying to download a feed for offline use while offline"
                    ),
                    in: window
                )
            }
            Haptics.warning()
            return
        }

        // The feed hasn't been imported yet (no account/site row). Nothing to
        // download against; bail quietly before showing the chooser.
        guard currentAccountAndSiteRowIds != nil else {
            Haptics.warning()
            return
        }

        // Present the count chooser. On Download it dismisses and starts the run
        // with the chosen cap; Cancel just dismisses (SwiftUI `@Environment`).
        let optionsViewModel = OfflineDownloadOptionsViewModel(
            preferencesService: preferencesService,
            onStart: { [weak self] maxPosts, archiveLinks in
                guard let self else { return }
                // Dismiss the chooser, then begin from a settled state so the
                // status pill appears cleanly (not over the closing chooser).
                dismiss(animated: true) { [weak self] in
                    self?.beginOfflineDownload(maxPosts: maxPosts, archiveLinks: archiveLinks)
                }
            }
        )
        let chooser = UIHostingController(
            rootView: OfflineDownloadOptionsView(viewModel: optionsViewModel)
        )
        chooser.modalPresentationStyle = .pageSheet
        if let presentationSheet = chooser.sheetPresentationController {
            presentationSheet.prefersGrabberVisible = true
            presentationSheet.preferredCornerRadius = 20
            presentationSheet.detents = [.medium(), .large()]
        }
        present(chooser, animated: true)
        Haptics.tap()
    }

    /// Starts predownloading the current feed and shows the non-blocking status
    /// pill. Called from the chooser's Download action with the chosen post cap and
    /// whether to also web-archive external-link pages. The offline / account
    /// guards already ran in ``startOfflineDownload()``, but the in-flight guard
    /// is rechecked here (the chooser is interactive, so a download could
    /// conceivably have started between presenting and confirming).
    private func beginOfflineDownload(maxPosts: Int, archiveLinks: Bool) {
        guard offlineDownloadTask == nil else { return }

        let keychainId = currentAccountKeychainId
        guard let ids = currentAccountAndSiteRowIds else {
            Haptics.warning()
            return
        }

        let feed = currentFeedHandle
        let scope = currentAccountScope
        let lemmyService = scope.lemmyService
        let commentSort = preferencesService.defaultCommentSortType
        let showNsfw = preferencesService.showNsfw
        let service = offlineDownloadService
        let instance = accountService.instanceActorId(forAccountKeychainId: keychainId)?.hostWithPort

        // The download keys each captured web archive under the SANITIZED link
        // URL, because the open path (`AppService.open(url:)`) sanitizes the
        // tapped link with this exact same `URLSanitizer.sanitize(_:config:)`
        // before looking the archive up. Snapshot the config now (off the
        // download task) so the closure is a pure `@Sendable` value-in/value-out
        // transform — capturing the config, not the service.
        let sanitizerConfig = preferencesService.urlSanitizerConfig
        let sanitizeURL: @Sendable (URL) -> URL = { url in
            URLSanitizer.sanitize(url, config: sanitizerConfig)
        }

        // The progress view model the pill binds to; the drain task pushes stream
        // values into it (the pill re-renders via observation), and its Cancel
        // routes back here.
        let progressViewModel = OfflineDownloadProgressViewModel(
            onCancel: { [weak self] in
                self?.cancelOfflineDownload()
            }
        )
        offlineDownloadProgressViewModel = progressViewModel

        // Show the non-blocking pill. The download runs regardless of whether the
        // pill is on screen; if there's somehow no window to anchor it to we still
        // start the run (the pill is presentation, not the engine).
        if let window = offlineDownloadWindow {
            OfflineDownloadStatusPresenter.shared.show(viewModel: progressViewModel, in: window)
        }

        Haptics.tap()

        // Drain the download stream on the main actor, updating the pill's view
        // model on each value. The terminal value (.finished / .failed /
        // .cancelled) ends the loop; cleanup dismisses the pill and shows the
        // result toast.
        offlineDownloadTask = Task { @MainActor [weak self] in
            let stream = service.download(
                feed: feed,
                lemmyService: lemmyService,
                accountId: ids.accountId,
                siteId: ids.siteId,
                commentSort: commentSort,
                showNsfw: showNsfw,
                maxPosts: maxPosts,
                archiveLinks: archiveLinks,
                instance: instance,
                sanitizeURL: sanitizeURL
            )
            for await progress in stream {
                if Task.isCancelled { break }
                // Break (don't `continue`) when the controller is gone: a
                // `continue` never suspends, so the loop would ghost-drain the
                // whole stream without honoring Task cancellation promptly.
                guard let self else { break }
                progressViewModel.progress = progress
                switch progress.phase {
                case .fetchingPosts, .downloadingContent:
                    continue
                case .finished, .failed, .cancelled:
                    finishOfflineDownload(with: progress)
                }
            }
        }
    }

    /// Cancels the in-flight download. Invoked only by the pill's ✕. The service
    /// keeps the progress stream alive so the draining task observes the terminal
    /// `.cancelled` and then dismisses the pill (via ``finishOfflineDownload(with:)``).
    func cancelOfflineDownload() {
        // Reflect the pending-cancel state immediately so the status line reads
        // "Cancelling…" while the in-flight item drains.
        offlineDownloadProgressViewModel?.progress.phase = .cancelled
        Task { await offlineDownloadService.cancelCurrentDownload() }
    }

    /// Terminal handler for a download run: tears down the drain task + view model,
    /// animates the pill out, then shows a result toast (mirrors the old sheet →
    /// toast handoff so the two never overlap).
    private func finishOfflineDownload(with progress: OfflineDownloadProgress) {
        offlineDownloadTask?.cancel()
        offlineDownloadTask = nil
        offlineDownloadProgressViewModel = nil

        let toast = resultToast(for: progress)
        OfflineDownloadStatusPresenter.shared.dismiss(animated: true) { [weak self] in
            self?.showOfflineDownloadToast(toast)
        }
    }

    /// The result toast copy for a terminal progress value, or nil when no toast
    /// is warranted.
    private func resultToast(for progress: OfflineDownloadProgress) -> String? {
        switch progress.phase {
        case .finished:
            // Report the posts actually saved (itemsCompleted), not the count
            // targeted (totalPosts); fall back to the fetched count when the
            // content phase had no completions.
            let count = progress.itemsCompleted > 0 ? progress.itemsCompleted : progress.postsFetched
            let format = NSLocalizedString(
                "Saved %d posts for offline browsing",
                comment: "Toast after an offline download finishes; %d is the post count"
            )
            return String(format: format, count)
        case .failed:
            return progress.failureMessage ?? NSLocalizedString(
                "Couldn't download the feed.",
                comment: "Fallback toast when an offline download fails"
            )
        case .cancelled:
            return NSLocalizedString(
                "Download cancelled",
                comment: "Toast after the user cancels an offline download"
            )
        case .fetchingPosts, .downloadingContent:
            // Not a terminal phase; no toast.
            return nil
        }
    }

    private func showOfflineDownloadToast(_ message: String?) {
        guard let message, let window = offlineDownloadWindow else { return }
        ToastPresenter.shared.show(message, in: window)
    }

    /// The window to anchor offline-download UI (pill + result toast) to. Prefers
    /// this controller's own window, but falls back to the app's active foreground
    /// window so the status pill and result toast still appear when the download
    /// finishes while the user has switched to another tab — the Posts-tab VC's
    /// `view.window` is nil when it's off-screen.
    private var offlineDownloadWindow: UIWindow? {
        if let window = view.window {
            return window
        }
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
        return windows.first(where: \.isKeyWindow) ?? windows.first
    }
}
