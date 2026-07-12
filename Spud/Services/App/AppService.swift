//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SafariServices
import SpudDataKit
import SpudUtilKit
import UIKit

@MainActor
protocol AppServiceType: AnyObject {
    /// Opens the post itself in a browser.
    func openInBrowser(
        serverPostId: Lemmy.PostID,
        originalPostUrl: String?,
        accountKeychainId: String,
        on viewController: UIViewController
    )

    /// Opens the given external link according to user preferences (e.g. opens in In-App Safari or external browser).
    func open(url: URL, on viewController: UIViewController) async

    /// Returns the SFSafariViewController configured as per user preferences, or
    /// `nil` when `url` is not an `http(s)` URL (SFSafariViewController traps on
    /// any other scheme). Meant to be used as a context-menu link preview, whose
    /// provider accepts a `nil` (no-preview) result.
    func safariViewControllerForPreview(url: URL) -> SFSafariViewController?

    /// The user's current URL-sanitizer config (front-end preferences). Read on the
    /// main actor to build a preference-aware video-host registry for playback.
    var urlSanitizerConfig: URLSanitizerConfig { get }
}

@MainActor
protocol HasAppService {
    var appService: AppServiceType { get }
}

@MainActor
class AppService: AppServiceType {
    private let preferencesService: PreferencesServiceType
    private let appDatabase: AppDatabase
    private let reachabilityMonitor: ReachabilityMonitoring

    /// Durable store of captured external-link web archives. Used to open a saved
    /// snapshot in the in-app reader when the user is offline. Optional because
    /// the store's init can fail if the App Group container is unavailable (same
    /// failure mode as `AppDatabase`); a nil store simply disables offline reading
    /// (links fall back to the normal Safari/browser path), it is never fatal.
    private let webArchiveStore: OfflineWebArchiveStore?

    // MARK: Functions

    init(
        preferencesService: PreferencesServiceType,
        appDatabase: AppDatabase,
        reachabilityMonitor: ReachabilityMonitoring,
        webArchiveStore: OfflineWebArchiveStore?
    ) {
        self.preferencesService = preferencesService
        self.appDatabase = appDatabase
        self.reachabilityMonitor = reachabilityMonitor
        self.webArchiveStore = webArchiveStore
    }

    func openInBrowser(
        serverPostId: Lemmy.PostID,
        originalPostUrl: String?,
        accountKeychainId: String,
        on viewController: UIViewController
    ) {
        guard let postUrl = LinkURL.forPost(
            instance: preferencesService.openInBrowserInstance,
            originalPostUrl: originalPostUrl,
            serverPostId: Int64(serverPostId),
            instanceActorId: appDatabase.accountInstanceActorIdSync(forKeychainId: accountKeychainId)
        ) else { return }
        presentSafariViewController(url: postUrl, on: viewController)
    }

    func safariViewControllerForPreview(url: URL) -> SFSafariViewController? {
        createSafariViewController(url: resolvedExternalURL(url))
    }

    var urlSanitizerConfig: URLSanitizerConfig {
        preferencesService.urlSanitizerConfig
    }

    func open(url: URL, on viewController: UIViewController) async {
        assert(url.spud == nil)

        let url = resolvedExternalURL(url)

        func openInSafariViewController() {
            presentSafariViewController(url: url, on: viewController)
        }

        // Offline-reader routing comes BEFORE the live Safari/browser branch.
        // The archive is only ever a fallback for no-connectivity: when online,
        // `resolveOpenStrategy` returns `.safari`/`.browser` (the live page is
        // always preferable to a frozen snapshot), so online behavior is
        // unchanged. We only look up the (sanitized) URL when offline.
        let archiveLookup = reachabilityMonitor.isOnline
            ? nil
            : webArchiveStore?.webArchiveLookupSync(forURL: url)
        let strategy = resolveOpenStrategy(
            isOnline: reachabilityMonitor.isOnline,
            hasArchive: archiveLookup != nil,
            preference: preferencesService.openExternalLinks
        )

        switch strategy {
        case .archiveReader:
            // `archiveLookup` is non-nil exactly when the strategy is .archiveReader.
            if let archiveLookup {
                presentOfflineReader(lookup: archiveLookup, originalURL: url, on: viewController)
            }

        case .offlineNoArchive:
            // SFSafariViewController can't load a page offline (it would show a
            // blank/error sheet). Rather than present a broken browser, reassure
            // the user with a brief toast and do nothing else.
            presentOfflineNoArchiveToast(on: viewController)

        case .safari:
            if preferencesService.openUniversalLinkInApp {
                let wasOpened = await UIApplication.shared.open(url, options: [.universalLinksOnly: true])
                if !wasOpened {
                    openInSafariViewController()
                }
            } else {
                openInSafariViewController()
            }

        case .browser:
            await UIApplication.shared.open(url)
        }
    }

    /// Presents the offline web archive reader modally, styled like the in-app
    /// browser. `originalURL` (the sanitized live link) backs Share and
    /// "Open in browser"; `lookup.fileURL` is the on-disk snapshot to render.
    private func presentOfflineReader(
        lookup: OfflineWebArchiveStore.Lookup,
        originalURL: URL,
        on viewController: UIViewController
    ) {
        let reader = OfflineWebArchiveReaderViewController.makeModal(
            archiveFileURL: lookup.fileURL,
            originalURL: originalURL,
            title: lookup.title
        )
        viewController.present(reader, animated: true)
    }

    /// Shows a brief, non-blocking toast explaining that the tapped link has no
    /// saved offline copy. Used in place of a broken offline SFSafariViewController.
    private func presentOfflineNoArchiveToast(on viewController: UIViewController) {
        guard let window = viewController.view.window else { return }
        ToastPresenter.shared.show(Self.offlineNoArchiveToast, in: window)
    }

    /// Toast copy for tapping an external link while offline with no saved archive.
    private static let offlineNoArchiveToast = NSLocalizedString(
        "This page isn't saved for offline.",
        comment: "Toast shown when opening an external link offline with no saved web archive"
    )

    /// Applies the outbound URL hygiene pipeline before a URL is opened or
    /// previewed. Returns the sanitized URL (or the original when the pipeline
    /// is disabled or no step applies).
    private func resolvedExternalURL(_ url: URL) -> URL {
        URLSanitizer.sanitize(url, config: preferencesService.urlSanitizerConfig)
    }

    /// Presents an in-app browser for `url` and records, on the presenter's
    /// navigation controller, how to re-open it. The right-edge forward gesture
    /// uses that to restore the link after it is dismissed (a fresh load — an
    /// SFSafariViewController instance cannot be reused once dismissed).
    private func presentSafariViewController(url: URL, on viewController: UIViewController) {
        guard let safariVC = createSafariViewController(url: url) else {
            // Not an http(s) URL — SFSafariViewController would trap. Hand it to
            // the system, which opens mailto:/tel:/custom schemes safely (and does
            // nothing for a scheme nothing can handle).
            Task { await UIApplication.shared.open(url) }
            return
        }

        viewController.navigationController?.pendingExternalLinkRestore = { [weak self, weak viewController] in
            guard let self, let viewController else { return }
            presentSafariViewController(url: url, on: viewController)
        }

        viewController.present(safariVC, animated: true)
    }

    /// Builds an in-app Safari view controller for `url`, or `nil` when `url` is
    /// not an `http(s)` URL. `SFSafariViewController(url:)` traps on any other
    /// scheme (e.g. a `spud-markdown://` mention or a `mailto:` link), so every
    /// caller must treat `nil` as "not openable in Safari" and fall back.
    private func createSafariViewController(url: URL) -> SFSafariViewController? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }

        let configuration = SFSafariViewController.Configuration()

        if preferencesService.openExternalLinksInSafariVCReaderMode {
            configuration.entersReaderIfAvailable = true
        }

        return SFSafariViewController(url: url, configuration: configuration)
    }
}
