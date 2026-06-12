//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import OSLog
import SpudDataKit
import SpudUIKit
import SwiftUI
import UIKit

private let logger = Logger.app

class SubscriptionsViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService &
        HasAppDatabase
    typealias NestedDependencies =
        PostListViewController.Dependencies &
        CommunityOrLoadingViewController.Dependencies
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    var accountService: AccountServiceType {
        dependencies.own.accountService
    }

    var appDatabase: AppDatabase {
        dependencies.own.appDatabase
    }

    // MARK: Private

    private let accountKeychainId: String
    private var viewModel: SubscriptionsViewModel!

    // MARK: Functions

    init(
        accountKeychainId: String,
        isSignedIn: Bool,
        dependencies: Dependencies
    ) {
        self.dependencies = (own: dependencies, nested: dependencies)
        self.accountKeychainId = accountKeychainId

        super.init(nibName: nil, bundle: nil)

        let accountRowId = appDatabase.accountRowIdSync(forKeychainId: accountKeychainId)

        viewModel = SubscriptionsViewModel(
            accountRowId: accountRowId,
            isSignedIn: isSignedIn,
            appDatabase: appDatabase,
            onFeedRequested: { [weak self] item in
                self?.handle(item: item)
            }
        )

        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        view.backgroundColor = Theme.background

        let contentVC = UIHostingController(rootView: SubscriptionsView(viewModel: self.viewModel))
        add(child: contentVC)
        addSubviewWithEdgeConstraints(child: contentVC)
    }

    private func handle(item: SubscriptionsViewItemType) {
        switch item {
        case let .listing(listingType):
            let sortType = accountService.defaultSortType(forAccountKeychainId: accountKeychainId)
            let feed = accountService.createFeed(
                forAccountKeychainId: accountKeychainId,
                feedType: .frontpage(
                    listingType: listingType,
                    sortType: sortType
                )
            )
            display(feed: feed)

        case let .community(row):
            // Open the full community screen (header + feed), not the bare
            // post list, so subscribe/unsubscribe and the community header are
            // available from the sidebar too.
            let communityVC = CommunityOrLoadingViewController(
                communityName: row.name,
                instance: row.instanceActorId,
                accountKeychainId: accountKeychainId,
                dependencies: dependencies.nested
            )
            navigationController?.pushViewController(communityVC, animated: true)

        case .saved:
            let sortType = accountService.defaultSortType(forAccountKeychainId: accountKeychainId)
            let feed = accountService.createFeed(
                forAccountKeychainId: accountKeychainId,
                feedType: .saved(sortType: sortType)
            )
            display(feed: feed)
        }
    }

    private func display(feed: FeedHandle) {
        let postListVC = PostListViewController(
            feed: feed,
            accountKeychainId: accountKeychainId,
            dependencies: dependencies.nested
        )
        navigationController?.pushViewController(postListVC, animated: true)
    }
}
