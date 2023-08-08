//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import CoreData
import SpudDataKit
import UIKit

class MainWindow: UIWindow {
    typealias OwnDependencies =
        HasAccountService
    typealias NestedDependencies =
        MainWindowSplitViewController.Dependencies &
        AccountViewController.Dependencies
    typealias Dependencies = OwnDependencies & NestedDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    private var accountService: AccountServiceType { dependencies.own.accountService }

    // MARK: Private

    private var accountInserted: AnyPublisher<LemmyAccount, Never> = NotificationCenter.default
        .publisher(for: .NSManagedObjectContextObjectsDidChange)
        .compactMap { notification -> LemmyAccount? in
            guard
                let insertedObjects = notification.userInfo?[NSInsertedObjectsKey] as? NSSet
            else {
                return nil
            }
            let accounts = insertedObjects.compactMap { $0 as? LemmyAccount }
            assert(accounts.count <= 1)
            return accounts.first
        }
        .eraseToAnyPublisher()

    private let tabBarController: MainWindowTabBarController
    private var splitViewController: MainWindowSplitViewController?

    private var disposables = Set<AnyCancellable>()

    // MARK: Functions

    init(
        windowScene: UIWindowScene,
        dependencies: Dependencies
    ) {
        self.dependencies = (own: dependencies, nested: dependencies)

        tabBarController = MainWindowTabBarController()

        super.init(windowScene: windowScene)

        accountInserted
            // run in the next tick instead of immediately
            // to avoid crash when calling saveContext() from within
            // NSManagedObjectContextObjectsDidChange which in turn
            // was triggered from saveContext().
            .receive(on: RunLoop.main)
            .sink { account in
                self.checkForUpdatedDefaultAccount(account)
            }
            .store(in: &disposables)

        let account = accountService.defaultAccount()
        recreateTabBarViewControllers(for: account)

        rootViewController = tabBarController
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func checkForUpdatedDefaultAccount(_ account: LemmyAccount) {
        guard account.isDefaultAccount else { return }
        assert(!account.isServiceAccount)

        recreateTabBarViewControllers(for: account)
    }

    private func recreateTabBarViewControllers(for account: LemmyAccount) {
        // Tab: Setup the split view controller
        let splitViewController = MainWindowSplitViewController(
            account: account,
            dependencies: dependencies.nested
        )
        self.splitViewController = splitViewController
        splitViewController.delegate = self

        // Tab: Setup the account view controller
        let accountViewController = AccountViewController(dependencies: dependencies.nested)
        let accountNavigationController = UINavigationController(rootViewController: accountViewController)

        // Tab: Setup the search view controller
        let searchViewController = SearchViewController()

        // Tab: Setup the preferences view controller
        let preferencesViewController = PreferencesViewController()

        // Setup the tab bar controller
        tabBarController.setViewControllers(
            [
                splitViewController,
                accountNavigationController,
                searchViewController,
                preferencesViewController,
            ],
            animated: false
        )
    }

    /// Pushes the given view controller as a detail view.
    private func pushDetail(viewController: UIViewController) {
        guard let splitViewController else {
            fatalError()
        }

        if splitViewController.isCollapsed {
            let navigationController = splitViewController.postListNavigationController
            navigationController.pushViewController(viewController, animated: true)
        } else {
            // we make a new navigation controller here to make UISplitVC replace the
            // detail screen instead of pushing a new PostDetail VC onto the stack.
            let navigationController = UINavigationController(rootViewController: viewController)
            splitViewController.showDetailViewController(navigationController, sender: self)
        }
    }

    func display(postId: Int32, using account: LemmyAccount) {
        // Switch to the post content tab
        tabBarController.selectedIndex = 0

        let postDetailVC = PostDetailOrEmptyViewController(
            account: account,
            dependencies: AppCoordinator.shared.dependencies
        )
        postDetailVC.startLoadingPost(postId: postId)

        pushDetail(viewController: postDetailVC)
    }

    func display(post: LemmyPost) {
        guard let postInfo = post.postInfo else {
            fatalError("We have post list with posts containing no info?")
        }

        let postDetailVC = PostDetailViewController(
            postInfo: postInfo,
            dependencies: dependencies.nested
        )

        pushDetail(viewController: postDetailVC)
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
