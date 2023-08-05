//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import UIKit

class MainWindowSplitViewController: UISplitViewController {
    typealias OwnDependencies =
        HasAccountService
    typealias NestedDependencies =
        SubscriptionsViewController.Dependencies &
        PostListViewController.Dependencies &
        PostDetailOrEmptyViewController.Dependencies
    typealias Dependencies = OwnDependencies & NestedDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    var accountService: AccountServiceType { dependencies.own.accountService }

    // MARK: Functions

    init(account: LemmyAccount, dependencies: Dependencies) {
        self.dependencies = (own: dependencies, nested: dependencies)

        super.init(style: .doubleColumn)

        // Setup the post list view controller (the primary part of split view controller)
        let subscriptionsVC = SubscriptionsViewController(
            account: account,
            dependencies: self.dependencies.nested
        )

        let feed = accountService
            .lemmyService(for: account)
            .createFeed(.frontpage(listingType: .all, sortType: .active))

        let postListVC = PostListViewController(
            feed: feed,
            dependencies: self.dependencies.nested
        )
        let primaryNavigationController = UINavigationController()
        primaryNavigationController.setViewControllers([subscriptionsVC, postListVC], animated: false)

        // Setup the post detail (the secondary part of split view controller)
        let postDetailVC = PostDetailOrEmptyViewController(
            account: account,
            dependencies: self.dependencies.nested
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
