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
    /// switcher beneath it (compact), and so the same instance is re-pushed —
    /// preserving the feed observation and letting the forward-stack reducer
    /// consume it. Exposed read-only so navigation entry points can reach the post
    /// list regardless of its position in the stack: it is the base in regular
    /// width (index 0) and sits above the feed switcher in compact (index 1).
    private(set) var postListViewController: PostListViewController!

    /// The Posts-tab feed switcher. Retained so the same instance can be
    /// re-inserted at the base of the compact stack on collapse (and stripped on
    /// expand). Exposed read-only so the split delegate (`MainWindow`) can move it
    /// between size classes. In compact it sits beneath the post list (revealed by
    /// the system back-swipe); in regular it is absent from the stack and feed
    /// selection happens through a transient navbar-title popover instead.
    private(set) var feedSwitcherViewController: FeedSwitcherViewController!

    /// The durable keychain id of the account backing this split. Retained so the
    /// feed-switcher factory can resolve the per-account default sort lazily.
    private let accountKeychainId: String

    // MARK: Functions

    init(
        accountKeychainId: String,
        isSignedIn: Bool,
        dependencies: Dependencies
    ) {
        self.dependencies = (own: dependencies, nested: dependencies)
        self.accountKeychainId = accountKeychainId

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

        // The feed switcher is the Posts-tab feed picker. In COMPACT width it sits
        // beneath the post list in this stack, so the system left-edge back gesture
        // reveals it (no custom gesture). In REGULAR width it is stripped from the
        // base (see `syncFeedSwitcherPresence()` and the split delegate) and feed
        // selection becomes a navbar-title popover instead. `makeFeedSwitcher`
        // builds both the beneath-the-list instance here and the transient popover
        // instance, so the callback wiring lives in exactly one place.
        //
        // `returnToList` here is the compact behaviour: bring the post list back to
        // the top of the stack (the user is on the revealed switcher), so it
        // animates in already showing the freshly chosen feed.
        let feedSwitcher = makeFeedSwitcher { [weak self] _ in
            guard let self, let postListVC = postListViewController else { return }
            if postListNavigationController.topViewController !== postListVC {
                postListNavigationController.pushViewController(postListVC, animated: true)
            }
        }
        feedSwitcherViewController = feedSwitcher

        // Wire the regular-width entry point: the post list's navbar-title control
        // presents a fresh feed switcher as a popover anchored to the title. Its
        // `returnToList` simply dismisses the popover.
        postListVC.onPresentFeedSwitcher = { [weak self, weak postListVC] anchor in
            guard let self, let postListVC else { return }
            let switcher = makeFeedSwitcher { presented in
                presented.dismiss(animated: true)
            }
            switcher.modalPresentationStyle = .popover
            switcher.preferredContentSize = CGSize(width: 320, height: 380)
            if let popover = switcher.popoverPresentationController {
                popover.sourceView = anchor
                popover.sourceRect = anchor.bounds
                popover.permittedArrowDirections = .up
            }
            postListVC.present(switcher, animated: true)
        }

        // Launch in the compact shape (`[switcher, postList]`). `viewIsAppearing`
        // strips the switcher when launched expanded (iPad); starting compact keeps
        // the shipped iPhone backstack correct even if that reconcile never runs.
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

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Reconcile the feed switcher with the resolved collapsed state. The
        // collapse/expand delegate callbacks own the size-class transitions, but
        // they do NOT fire for the INITIAL launch state — an iPad launches already
        // expanded (it never "transitions" to expanded, so `splitViewControllerDidExpand`
        // is not called) and must drop the switcher from the primary base, while an
        // iPhone launches collapsed and keeps it beneath. `isCollapsed` is only
        // reliable after the split has laid out its columns, so this runs here.
        // It is idempotent and only mutates the stack when a change is actually
        // needed, so it never fights the delegate (which already leaves the switcher
        // in the correct state for the new size class).
        syncFeedSwitcherPresence()
    }

    /// Builds a fully-wired Posts-tab feed switcher. Both the retained
    /// beneath-the-list switcher (compact) and the transient navbar-title popover
    /// (regular) are produced here so the callback wiring lives in exactly one
    /// place (DRY).
    ///
    /// `returnToList` runs after the user picks a feed or chooses "Browse all
    /// communities", to return focus to the post list: re-push it beneath in the
    /// compact stack, or dismiss the popover in the regular size class. It is
    /// handed the switcher instance that fired it (the popover dismisses itself).
    private func makeFeedSwitcher(
        returnToList: @escaping (FeedSwitcherViewController) -> Void
    ) -> FeedSwitcherViewController {
        let accountService = accountService
        let accountKeychainId = accountKeychainId
        let feedSwitcher = FeedSwitcherViewController(
            currentFeedType: { [weak self] in self?.postListViewController?.currentFeedType },
            defaultSortType: { accountService.defaultSortType(forAccountKeychainId: accountKeychainId) }
        )
        feedSwitcher.onSelectFeedType = { [weak self, weak feedSwitcher] feedType in
            guard let self, let feedSwitcher, let postListVC = postListViewController else { return }
            // Switch first so the list is already showing the new feed when it returns.
            postListVC.showFeed(feedType)
            returnToList(feedSwitcher)
        }
        feedSwitcher.onBrowseAllCommunities = { [weak self, weak feedSwitcher] in
            guard let self, let feedSwitcher else { return }
            // Return focus to the post list first — in compact this restores the
            // Posts tab so coming back to it does not land on the bare switcher —
            // then jump to the Communities tab (index 1).
            returnToList(feedSwitcher)
            tabBarController?.selectedIndex = 1
        }
        return feedSwitcher
    }

    /// Inserts or removes the feed switcher from the shared post-list stack to
    /// match the current collapsed state, without touching any detail content. In
    /// compact (collapsed) the switcher belongs at index 0 beneath the post list so
    /// the system back-swipe reveals it; in regular (expanded) it must be absent so
    /// the always-visible primary column never pops to it (feed selection is the
    /// navbar-title popover instead). Idempotent.
    private func syncFeedSwitcherPresence() {
        guard let feedSwitcher = feedSwitcherViewController else { return }
        var stack = postListNavigationController.viewControllers
        let hasSwitcher = stack.contains(feedSwitcher)
        if isCollapsed {
            guard !hasSwitcher else { return }
            stack.insert(feedSwitcher, at: 0)
        } else {
            guard hasSwitcher else { return }
            stack.removeAll { $0 === feedSwitcher }
        }
        postListNavigationController.setViewControllers(stack, animated: false)
    }
}
