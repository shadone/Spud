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

    /// Retained so it survives being popped off the stack to reveal the feed
    /// switcher beneath it, and so the same instance is re-pushed — preserving
    /// the feed observation and letting the forward-stack reducer consume it.
    /// Exposed read-only so navigation entry points can reach the post list
    /// regardless of its position in the stack — it now sits at index 1, beneath
    /// the feed switcher.
    private(set) var postListViewController: PostListViewController!

    // MARK: Functions

    init(
        accountKeychainId: String,
        isSignedIn: Bool,
        dependencies: Dependencies
    ) {
        self.dependencies = (own: dependencies, nested: dependencies)

        super.init(style: .doubleColumn)

        let accountService = accountService
        let feed = accountService.createDefaultFeed(forAccountKeychainId: accountKeychainId)

        let postListVC = PostListViewController(
            feed: feed,
            accountKeychainId: accountKeychainId,
            showsQuickSwitch: true,
            dependencies: self.dependencies.nested
        )
        postListViewController = postListVC

        // The feed switcher sits beneath the post list in the Posts-tab stack, so
        // the system left-edge back gesture reveals it (no custom gesture). The
        // post list is shown on top; swiping back pops to the switcher.
        let nav = postListNavigationController
        let feedSwitcher = FeedSwitcherViewController(
            currentFeedType: { [weak postListVC] in postListVC?.currentFeedType },
            defaultSortType: { accountService.defaultSortType(forAccountKeychainId: accountKeychainId) }
        )
        feedSwitcher.onSelectFeedType = { [weak postListVC, weak nav] feedType in
            guard let postListVC, let nav else { return }
            // Switch first so the list animates back in already showing the new feed.
            postListVC.showFeed(feedType)
            nav.pushViewController(postListVC, animated: true)
        }
        feedSwitcher.onBrowseAllCommunities = { [weak self, weak postListVC, weak nav] in
            guard let self else { return }
            // Restore the Posts tab to its feed before leaving, so returning to
            // the tab does not land on the bare switcher.
            if let postListVC, let nav, nav.topViewController !== postListVC {
                nav.pushViewController(postListVC, animated: false)
            }
            tabBarController?.selectedIndex = 1
        }
        postListNavigationController.setViewControllers([feedSwitcher, postListVC], animated: false)

        // Setup the post detail (the secondary part of split view controller)
        let postDetailVC = PostDetailOrEmptyViewController(
            accountKeychainId: accountKeychainId,
            dependencies: self.dependencies.nested
        )
        postDetailNavigationController.setViewControllers([postDetailVC], animated: false)

        setViewController(postListNavigationController, for: .primary)
        setViewController(postDetailNavigationController, for: .secondary)
        setViewController(postListNavigationController, for: .compact)

        // Right-edge forward gesture (restore a popped screen) on both columns' stacks.
        postListNavigationController.enableForwardNavigationGesture()
        postDetailNavigationController.enableForwardNavigationGesture()

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
