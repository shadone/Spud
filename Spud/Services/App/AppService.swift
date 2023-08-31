//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SafariServices
import SpudDataKit
import UIKit

protocol AppServiceType: AnyObject {
    /// Opens the post itself in a browser.
    func openInBrowser(post: LemmyPost, on viewController: UIViewController) async

    /// Opens the given external link according to user preferences (e.g. opens in In-App Safari or external browser).
    func open(url: URL, on viewController: UIViewController) async

    /// Returns the SFSafariViewController configured as per user preferences. This is meant to be used in context menu link previews.
    func safariViewControllerForPreview(url: URL) -> SFSafariViewController
}

protocol HasAppService {
    var appService: AppServiceType { get }
}

class AppService: AppServiceType {
    private let preferencesService: PreferencesServiceType

    // MARK: Functions

    init(preferencesService: PreferencesServiceType) {
        self.preferencesService = preferencesService
    }

    func openInBrowser(post: LemmyPost, on viewController: UIViewController) {
        let safariVC = SFSafariViewController(url: post.localLemmyUiUrl)
        viewController.present(safariVC, animated: true)
    }

    func safariViewControllerForPreview(url: URL) -> SFSafariViewController {
        createSafariViewController(url: url)
    }

    @MainActor
    func open(url: URL, on viewController: UIViewController) async {
        assert(url.spud == nil)

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

    private func createSafariViewController(url: URL) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()

        if preferencesService.openExternalLinksInSafariVCReaderMode {
            configuration.entersReaderIfAvailable = true
        }

        return SFSafariViewController(url: url, configuration: configuration)
    }
}
