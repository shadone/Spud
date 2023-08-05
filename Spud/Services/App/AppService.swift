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

    /// Opens an external link in a browser.
    func open(url: URL, on viewController: UIViewController) async
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

    @MainActor func open(url: URL, on viewController: UIViewController) async {
        assert(url.spud == nil)

        func openInSafariViewController() {
            let configuration = SFSafariViewController.Configuration()

            if preferencesService.openExternalLinksInSafariVCReaderMode {
                configuration.entersReaderIfAvailable = true
            }

            let safariVC = SFSafariViewController(url: url, configuration: configuration)
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
}
