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
/// Download the chooser dismisses and ``beginOfflineDownload(maxPosts:)`` runs:
/// it resolves the current feed's account/site identifiers and the comment-sort
/// + show-NSFW preferences, presents a compact progress sheet, and drains the
/// service's `AsyncStream` on the main actor — pushing each value into the
/// sheet's view model. On `.finished` / `.failed` / `.cancelled` it dismisses
/// the sheet and shows a toast.
///
/// **Dismiss cancels the download.** A swipe-to-dismiss (or the Cancel button)
/// must not leave a runaway background download: both paths call
/// `cancelCurrentDownload()`, and the draining task keeps reading until the
/// terminal `.cancelled` lands before the sheet is gone. The drain task is also
/// torn down in `deinit`, so the download can't outlive the controller.
extension PostListViewController {
    /// Presents the "Download for offline" chooser (post-count picker) for the
    /// current feed. No-ops (with a brief toast) when offline, when a download is
    /// already running, or when the feed's account can't be resolved — the same
    /// guards the actual download applies, checked up front so the chooser never
    /// appears over a doomed run.
    func startOfflineDownload() {
        // Don't start a second download over a live one — the actor would reject
        // it anyway, but bailing here keeps the existing sheet in front.
        guard offlineDownloadTask == nil else { return }

        // You can't predownload without a connection. Surface a brief toast
        // rather than opening a chooser whose download would immediately fail.
        guard reachabilityMonitor.isOnline else {
            if let window = view.window {
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
        guard appDatabase.accountAndSiteRowIdSync(forKeychainId: currentAccountKeychainId) != nil else {
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
                // progress sheet presents cleanly (not over the closing chooser).
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

    /// Starts predownloading the current feed and presents the progress sheet.
    /// Called from the chooser's Download action with the chosen post cap and
    /// whether to also web-archive external-link pages. The offline / account
    /// guards already ran in ``startOfflineDownload()``, but the in-flight guard
    /// is rechecked here (the chooser is interactive, so a download could
    /// conceivably have started between presenting and confirming).
    private func beginOfflineDownload(maxPosts: Int, archiveLinks: Bool) {
        guard offlineDownloadTask == nil else { return }

        let keychainId = currentAccountKeychainId
        guard let ids = appDatabase.accountAndSiteRowIdSync(forKeychainId: keychainId) else {
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

        // The progress view model the sheet binds to; the drain task pushes
        // stream values into it, and its Cancel button routes back here.
        let progressViewModel = OfflineDownloadProgressViewModel(
            onCancel: { [weak self] in
                self?.cancelOfflineDownload()
            }
        )
        offlineDownloadProgressViewModel = progressViewModel

        let sheet = makeOfflineDownloadSheet(viewModel: progressViewModel)
        present(sheet, animated: true)

        Haptics.tap()

        // Drain the download stream on the main actor, updating the sheet on each
        // value. The terminal value (.finished / .failed / .cancelled) ends the
        // loop; cleanup dismisses the sheet and shows the result toast.
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

    /// Cancels the in-flight download. The service keeps the progress stream
    /// alive so the draining task observes the terminal `.cancelled` and then
    /// dismisses the sheet (via ``finishOfflineDownload(with:)``).
    func cancelOfflineDownload() {
        // Reflect the pending-cancel state immediately so the status line reads
        // "Cancelling…" while the in-flight item drains.
        offlineDownloadProgressViewModel?.progress.phase = .cancelled
        Task { await offlineDownloadService.cancelCurrentDownload() }
    }

    /// Handles the user swiping the progress sheet away mid-download. The sheet
    /// is already gone, so there's nothing left to drain into — cancel the run,
    /// tear down the drain task, and confirm with a brief toast. We tear the task
    /// down here (rather than waiting for the `.cancelled` terminal) because the
    /// sheet no longer needs the intermediate updates.
    func handleOfflineSheetSwipedAway() {
        guard offlineDownloadTask != nil else { return }
        offlineDownloadTask?.cancel()
        offlineDownloadTask = nil
        offlineDownloadProgressViewModel = nil
        // Cancelling the actor's work task stops the in-flight network work even
        // though we've stopped draining the stream.
        Task { await offlineDownloadService.cancelCurrentDownload() }
        showOfflineDownloadToast(NSLocalizedString(
            "Download cancelled",
            comment: "Toast after the user swipes away the offline-download sheet"
        ))
    }

    /// Builds the page-sheet hosting the SwiftUI progress view, with a small
    /// content-fitting detent and a visible grabber: swipe-to-dismiss is
    /// intentional and cancels the download via the presentation-controller
    /// delegate (see ``handleOfflineSheetSwipedAway()``), as does the Cancel
    /// button — neither leaves a runaway background download.
    private func makeOfflineDownloadSheet(
        viewModel: OfflineDownloadProgressViewModel
    ) -> UIViewController {
        let host = UIHostingController(
            rootView: OfflineDownloadProgressView(viewModel: viewModel)
        )
        host.modalPresentationStyle = .pageSheet
        // Assign the dismiss delegate to the `sheetPresentationController` (a
        // `UIPresentationController` subclass, non-nil once the style is
        // `.pageSheet`), NOT `presentationController` — the latter is nil until
        // UIKit vends it during `present(...)`, so assigning there no-ops and
        // `presentationControllerDidDismiss` never fires on a swipe-away.
        host.sheetPresentationController?.delegate = offlineDownloadSheetDelegate
        if let presentationSheet = host.sheetPresentationController {
            presentationSheet.prefersGrabberVisible = true
            presentationSheet.preferredCornerRadius = 20
            // A compact, content-fitting detent on iOS 16+; medium otherwise.
            if #available(iOS 16.0, *) {
                presentationSheet.detents = [
                    .custom { _ in 240 },
                    .medium(),
                ]
            } else {
                presentationSheet.detents = [.medium()]
            }
        }
        return host
    }

    /// Terminal handler for a download run: dismisses the sheet, tears down the
    /// drain task + view model, and shows a result toast.
    private func finishOfflineDownload(with progress: OfflineDownloadProgress) {
        offlineDownloadTask?.cancel()
        offlineDownloadTask = nil
        offlineDownloadProgressViewModel = nil

        // Dismiss the sheet (if it's still up), then toast the outcome.
        let toast = resultToast(for: progress)
        if presentedViewController is UIHostingController<OfflineDownloadProgressView> {
            dismiss(animated: true) { [weak self] in
                self?.showOfflineDownloadToast(toast)
            }
        } else {
            showOfflineDownloadToast(toast)
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
        guard let message, let window = view.window else { return }
        ToastPresenter.shared.show(message, in: window)
    }
}

/// Detects an interactive (swipe) dismissal of the offline-download sheet so the
/// in-flight download is cancelled rather than left running headless. The
/// Cancel button dismisses via the terminal `.cancelled` path instead; this
/// covers only the user dragging the sheet away mid-download.
///
/// Conforms to `UISheetPresentationControllerDelegate` (which refines
/// `UIAdaptivePresentationControllerDelegate`) so it can be assigned to the
/// host's `sheetPresentationController.delegate`, whose type is the sheet
/// variant; `presentationControllerDidDismiss` is inherited from the adaptive
/// protocol and still fires on swipe-away.
@MainActor
final class OfflineDownloadSheetDismissDelegate: NSObject, UISheetPresentationControllerDelegate {
    /// Invoked when the sheet is interactively dismissed. Set by the controller.
    var onInteractiveDismiss: (() -> Void)?

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        onInteractiveDismiss?()
    }
}
