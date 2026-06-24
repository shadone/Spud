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
        serverPostId: Components.Schemas.PostID,
        originalPostUrl: String?,
        accountKeychainId: String,
        on viewController: UIViewController
    ) async

    /// Opens the given external link according to user preferences (e.g. opens in In-App Safari or external browser).
    func open(url: URL, on viewController: UIViewController) async

    /// Returns the SFSafariViewController configured as per user preferences. This is meant to be used in context menu link previews.
    func safariViewControllerForPreview(url: URL) -> SFSafariViewController
}

@MainActor
protocol HasAppService {
    var appService: AppServiceType { get }
}

@MainActor
class AppService: AppServiceType {
    private let preferencesService: PreferencesServiceType
    private let appDatabase: AppDatabase

    // MARK: Functions

    init(preferencesService: PreferencesServiceType, appDatabase: AppDatabase) {
        self.preferencesService = preferencesService
        self.appDatabase = appDatabase
    }

    func openInBrowser(
        serverPostId: Components.Schemas.PostID,
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

    func safariViewControllerForPreview(url: URL) -> SFSafariViewController {
        createSafariViewController(url: resolvedExternalURL(url))
    }

    func open(url: URL, on viewController: UIViewController) async {
        assert(url.spud == nil)

        let url = resolvedExternalURL(url)

        func openInSafariViewController() {
            presentSafariViewController(url: url, on: viewController)
        }

        switch preferencesService.openExternalLinks {
        case .safariViewController:
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
        let safariVC = createSafariViewController(url: url)

        viewController.navigationController?.pendingExternalLinkRestore = { [weak self, weak viewController] in
            guard let self, let viewController else { return }
            presentSafariViewController(url: url, on: viewController)
        }

        viewController.present(safariVC, animated: true)
    }

    private func createSafariViewController(url: URL) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()

        if preferencesService.openExternalLinksInSafariVCReaderMode {
            configuration.entersReaderIfAvailable = true
        }

        return SFSafariViewController(url: url, configuration: configuration)
    }
}
