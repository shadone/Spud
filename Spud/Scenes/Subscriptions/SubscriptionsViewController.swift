//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import OSLog
import SpudDataKit
import SwiftUI
import UIKit

private let logger = Logger.app

class SubscriptionsViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService &
        HasAppDatabase
    typealias NestedDependencies =
        PostListViewController.Dependencies
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    var accountService: AccountServiceType {
        dependencies.own.accountService
    }

    var appDatabase: AppDatabase {
        dependencies.own.appDatabase
    }

    // MARK: Private

    private let account: LemmyAccount
    private var viewModel: SubscriptionsViewModel!

    // MARK: Functions

    init(account: LemmyAccount, dependencies: Dependencies) {
        self.dependencies = (own: dependencies, nested: dependencies)

        self.account = account

        super.init(nibName: nil, bundle: nil)

        let accountRowId = appDatabase.accountRowIdSync(forKeychainId: account.id)

        viewModel = SubscriptionsViewModel(
            accountRowId: accountRowId,
            isSignedIn: !account.isSignedOutAccountType,
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
        view.backgroundColor = .systemBackground

        let contentVC = UIHostingController(rootView: SubscriptionsView(viewModel: self.viewModel))
        add(child: contentVC)
        addSubviewWithEdgeConstraints(child: contentVC)
    }

    private func handle(item: SubscriptionsViewItemType) {
        let dataService = accountService.lemmyDataService(for: account)
        let feed: LemmyFeed
        switch item {
        case let .listing(listingType):
            feed = dataService.createFeed(listingType: listingType)
        case let .community(row):
            feed = dataService.createFeed(.community(
                communityName: row.name,
                instance: row.instanceActorId,
                sortType: .Active
            ))
        }
        display(feed: feed)
    }

    private func display(feed: LemmyFeed) {
        let postListVC = PostListViewController(feed: feed, dependencies: dependencies.nested)
        navigationController?.pushViewController(postListVC, animated: true)
    }
}
