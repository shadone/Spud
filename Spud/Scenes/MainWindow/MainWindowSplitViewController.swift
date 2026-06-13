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

    private var accountService: AccountServiceType {
        dependencies.own.accountService
    }

    // MARK: Public

    let postListNavigationController = UINavigationController()
    let postDetailNavigationController = UINavigationController()

    // MARK: Functions

    init(
        accountKeychainId: String,
        isSignedIn: Bool,
        dependencies: Dependencies
    ) {
        self.dependencies = (own: dependencies, nested: dependencies)

        super.init(style: .doubleColumn)

        // The feed is the root of the Posts tab. Subscription management and
        // community browsing now live in their own Communities tab; fast
        // feed/community switching is handled by the quick-switch drawer opened
        // from the feed (replacing the old subscriptions-list-as-root model,
        // which left the list unreachable on iPhone once compose took the back
        // button).
        let feed = accountService.createDefaultFeed(forAccountKeychainId: accountKeychainId)

        let postListVC = PostListViewController(
            feed: feed,
            accountKeychainId: accountKeychainId,
            dependencies: self.dependencies.nested
        )
        postListNavigationController.setViewControllers([postListVC], animated: false)

        // Setup the post detail (the secondary part of split view controller)
        let postDetailVC = PostDetailOrEmptyViewController(
            accountKeychainId: accountKeychainId,
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
