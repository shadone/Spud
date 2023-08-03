//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import CoreData
import UIKit
import SpudWidgetData
import WidgetKit

class MainWindow: UIWindow {
    typealias OwnDependencies =
        HasAccountService
    typealias NestedDependencies =
        MainWindowSplitViewController.Dependencies &
        AccountViewController.Dependencies
    typealias Dependencies = OwnDependencies & NestedDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    var accountService: AccountServiceType { dependencies.own.accountService }

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

    private var accountDeleted: AnyPublisher<LemmyAccount, Never> = NotificationCenter.default
        .publisher(for: .NSManagedObjectContextObjectsDidChange)
        .compactMap { notification -> LemmyAccount? in
            guard
                let deletedObjects = notification.userInfo?[NSDeletedObjectsKey] as? NSSet
            else {
                return nil
            }
            let accounts = deletedObjects.compactMap { $0 as? LemmyAccount }
            assert(accounts.count <= 1)
            return accounts.first
        }
        .eraseToAnyPublisher()

    private var accountUpdated: AnyPublisher<Void, Never> = NotificationCenter.default
        .publisher(for: .NSManagedObjectContextObjectsDidChange)
        .compactMap { notification -> Void? in
            guard
                let updatedObjects = notification.userInfo?[NSUpdatedObjectsKey] as? NSSet
            else {
                return nil
            }
            let accounts = updatedObjects.compactMap { $0 as? LemmyAccount }
            return accounts.isEmpty ? nil : ()
        }
        .eraseToAnyPublisher()

    private var feedUpdated: AnyPublisher<LemmyFeed, Never> = NotificationCenter.default
        .publisher(for: .NSManagedObjectContextObjectsDidChange)
        .compactMap { notification -> LemmyFeed? in
            guard
                let updatedObjects = notification.userInfo?[NSUpdatedObjectsKey] as? NSSet
            else {
                return nil
            }
            let feeds = updatedObjects.compactMap { $0 as? LemmyFeed }
            assert(feeds.count <= 1)
            return feeds.first
        }
        .eraseToAnyPublisher()

    private let tabBarController: MainWindowTabBarController

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

        feedUpdated
            .sink { feed in
                guard
                    let topPosts = feed.pages
                        .sorted(by: { $0.index < $1.index })
                        .first?
                        .pageElements
                        .sorted(by: { $0.index < $1.index })
                        .prefix(3)
                        .map(\.post)
                else {
                    return
                }

                let value = TopPosts(posts: topPosts.map { post in
                    let postType: Post.PostType
                    if let thumbnailUrl = post.thumbnailUrl {
                        postType = .image(thumbnailUrl)
                    } else {
                        postType = .text
                    }

                    // TODO:
                    let postUrl = URL(string: "spud://foobar/post/\(post.localPostId)")!

                    return .init(
                        spudUrl: postUrl,
                        title: post.title,
                        type: postType,
                        community: .init(name: post.communityName, site: "XXX"),
                        score: post.score,
                        numberOfComments: post.numberOfComments
                    )
                })

                WidgetDataProvider.shared.write(value)

                WidgetCenter.shared.reloadAllTimelines()
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
