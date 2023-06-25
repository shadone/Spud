//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

class MainWindow: UIWindow {
    typealias Dependencies =
        HasAccountService &
        HasSiteService &
        SubscriptionsViewController.Dependencies &
        PostListViewController.Dependencies &
        PostDetailOrEmptyViewController.Dependencies &
        AccountViewController.Dependencies
    let dependencies: Dependencies

    // MARK: Private

    init(
        windowScene: UIWindowScene,
        dependencies: Dependencies
    ) {
        self.dependencies = dependencies

        let tchncs = URL(string: "https://discuss.tchncs.de")!

        let site = dependencies.siteService.site(for: tchncs)!
        let account = dependencies.accountService.accountForSignedOut(at: site)

        // Tab: Setup the split view controller
        let splitViewController = MainWindowSplitViewController(
            account: account,
            dependencies: dependencies
        )

        // Tab: Setup the account view controller
        let accountViewController = AccountViewController(dependencies: dependencies)
        let accountNavigationController = UINavigationController(rootViewController: accountViewController)

        // Tab: Setup the search view controller
        let searchViewController = SearchViewController()

        // Tab: Setup the preferences view controller
        let preferencesViewController = PreferencesViewController()

        // Setup the tab bar controller
        let tabBarController = MainWindowTabBarController()
        tabBarController.setViewControllers(
            [
                splitViewController,
                accountNavigationController,
                searchViewController,
                preferencesViewController,
            ],
            animated: false
        )

        super.init(windowScene: windowScene)

        splitViewController.delegate = self

        rootViewController = tabBarController
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension MainWindow: UISplitViewControllerDelegate {
    func splitViewControllerDidCollapse(_ svc: UISplitViewController) {
        // TODO: move the navigation stack from Primary column to Compact column
        // when collapsing i.e. transitioning to compact state and back.
        //
        // This happens when e.g. on iPhone when start navigating - press on a post
        // in the PostList, we push to Primary column's NC; Then rotate the phone to landscape
        // and suddenly Detail VC is visible - but the Primary NC still has the navigation
        // stack that should instead be shown in the Secondary column.
    }
}
