//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

class MainWindow: UIWindow {
    private let secondaryNavigationController: UINavigationController

    override init(
        windowScene: UIWindowScene
    ) {
        let tchncs = URL(string: "https://discuss.tchncs.de")!

        let accountService = AppDelegate.shared.dependencies.accountService
        let account = accountService.accountForSignedOut(instanceUrl: tchncs)
        let lemmyService = accountService.lemmyService(for: account)

        // Setup the post list view controller (the primary part of split view controller)
        let subscriptionsVC = SubscriptionsViewController(
            account: account,
            dependencies: AppDelegate.shared.dependencies
        )

        let feed = lemmyService.createFeed(.frontpage(listingType: .all, sortType: .active))

        let postListVC = PostListViewController(
            feed: feed,
            dependencies: AppDelegate.shared.dependencies
        )
        let primaryNavigationController = UINavigationController()
        primaryNavigationController.setViewControllers([subscriptionsVC, postListVC], animated: false)

        // Setup the post detail (the secondary part of split view controller)
        let postDetailVC = PostDetailOrEmptyViewController(
            account: account,
            dependencies: AppDelegate.shared.dependencies
        )
        secondaryNavigationController = UINavigationController(rootViewController: postDetailVC)

        // Setup the split view controller
        let splitViewController = UISplitViewController(style: .doubleColumn)
        splitViewController.setViewController(primaryNavigationController, for: .primary)
        splitViewController.setViewController(secondaryNavigationController, for: .secondary)
        splitViewController.setViewController(primaryNavigationController, for: .compact)
        splitViewController.preferredDisplayMode = .oneBesideSecondary
        splitViewController.preferredSplitBehavior = .tile

        super.init(windowScene: windowScene)

        rootViewController = splitViewController
        splitViewController.delegate = self
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