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
        PostDetailOrEmptyViewController.Dependencies &
        PostListViewController.Dependencies &
        SubscriptionsViewController.Dependencies
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    private var accountService: AccountServiceType { dependencies.own.accountService }

    // MARK: Public

    let postListNavigationController = UINavigationController()
    let postDetailNavigationController = UINavigationController()

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
            .lemmyDataService(for: account)
            .createFeed()

        let postListVC = PostListViewController(
            feed: feed,
            dependencies: self.dependencies.nested
        )
        postListNavigationController.setViewControllers([subscriptionsVC, postListVC], animated: false)

        // Setup the post detail (the secondary part of split view controller)
        let postDetailVC = PostDetailOrEmptyViewController(
            account: account,
            dependencies: self.dependencies.nested
        )
        postDetailNavigationController.setViewControllers([postDetailVC], animated: false)

        setViewController(postListNavigationController, for: .primary)
        setViewController(postDetailNavigationController, for: .secondary)
        setViewController(postListNavigationController, for: .compact)
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
