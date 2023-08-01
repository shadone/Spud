//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SafariServices
import UIKit

protocol AppServiceType: AnyObject {
    /// Opens the post itself in a browser.
    func openInBrowser(post: LemmyPost, on viewController: UIViewController)

    /// Opens an external link in a browser.
    func open(url: URL, on viewController: UIViewController)
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

    func open(url: URL, on viewController: UIViewController) {
        assert(url.spud == nil)

        switch preferencesService.openExternalLinks {
        case .safariViewController:
            let configuration = SFSafariViewController.Configuration()

            if preferencesService.openExternalLinksInSafariVCReaderMode {
                configuration.entersReaderIfAvailable = true
            }

            let safariVC = SFSafariViewController(url: url, configuration: configuration)
            viewController.present(safariVC, animated: true)

        case .browser:
            UIApplication.shared.open(url)
        }
    }
}
