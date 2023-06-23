//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import UIKit

class MainWindowSplitViewController: UISplitViewController {
    typealias Dependencies =
    HasAccountService &
    SubscriptionsViewController.Dependencies &
    PostListViewController.Dependencies &
    PostDetailOrEmptyViewController.Dependencies
    let dependencies: Dependencies

    // MARK: Functions

    init(account: LemmyAccount, dependencies: Dependencies) {
        self.dependencies = dependencies

        super.init(style: .doubleColumn)

        // Setup the post list view controller (the primary part of split view controller)
        let subscriptionsVC = SubscriptionsViewController(
            account: account,
            dependencies: dependencies
        )

        let lemmyService = dependencies.accountService.lemmyService(for: account)

        let feed = lemmyService.createFeed(.frontpage(listingType: .all, sortType: .active))

        let postListVC = PostListViewController(
            feed: feed,
            dependencies: dependencies
        )
        let primaryNavigationController = UINavigationController()
        primaryNavigationController.setViewControllers([subscriptionsVC, postListVC], animated: false)

        // Setup the post detail (the secondary part of split view controller)
        let postDetailVC = PostDetailOrEmptyViewController(
            account: account,
            dependencies: dependencies
        )
        let secondaryNavigationController = UINavigationController(rootViewController: postDetailVC)

        setViewController(primaryNavigationController, for: .primary)
        setViewController(secondaryNavigationController, for: .secondary)
        setViewController(primaryNavigationController, for: .compact)
        preferredDisplayMode = .oneBesideSecondary
        preferredSplitBehavior = .tile

        tabBarItem.title = "Posts"
        tabBarItem.image = UIImage(systemName: "doc.richtext")!
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
