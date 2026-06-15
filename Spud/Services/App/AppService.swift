//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SafariServices
import SpudDataKit
import UIKit

@MainActor
protocol AppServiceType: AnyObject {
    /// Opens the post itself in a browser.
    func openInBrowser(
        serverPostId: Components.Schemas.PostID,
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
        accountKeychainId: String,
        on viewController: UIViewController
    ) {
        guard
            let actorId = appDatabase.accountInstanceActorIdSync(forKeychainId: accountKeychainId),
            let instanceUrl = URL(string: actorId)
        else { return }
        let postUrl = instanceUrl.appending(path: "post/\(serverPostId)")
        let safariVC = SFSafariViewController(url: postUrl)
        viewController.present(safariVC, animated: true)
    }

    func safariViewControllerForPreview(url: URL) -> SFSafariViewController {
        createSafariViewController(url: resolvedExternalURL(url))
    }

    func open(url: URL, on viewController: UIViewController) async {
        assert(url.spud == nil)

        let url = resolvedExternalURL(url)

        func openInSafariViewController() {
            let safariVC = createSafariViewController(url: url)
            viewController.present(safariVC, animated: true)
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

    /// Applies user-configured external-link rewrites (currently the optional
    /// twitter.com / x.com to xcancel.com redirect) before a URL is opened or
    /// previewed. Returns the URL unchanged when no rewrite applies.
    private func resolvedExternalURL(_ url: URL) -> URL {
        guard preferencesService.rewriteTwitterLinksToXcancel else { return url }
        return url.rewritingTwitterToXcancel()
    }

    private func createSafariViewController(url: URL) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()

        if preferencesService.openExternalLinksInSafariVCReaderMode {
            configuration.entersReaderIfAvailable = true
        }

        return SFSafariViewController(url: url, configuration: configuration)
    }
}
